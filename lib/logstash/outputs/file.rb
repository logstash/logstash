# encoding: utf-8
require "logstash/namespace"
require "logstash/outputs/base"
require "zlib"

# This output will write events to files on disk. You can use fields
# from the event as parts of the filename and/or path.
class LogStash::Outputs::File < LogStash::Outputs::Base

  config_name "file"
  milestone 2

  # The path to the file to write. Event fields can be used here, 
  # like "/var/log/logstash/%{host}/%{application}"
  # One may also utilize the path option for date-based log 
  # rotation via the joda time format. This will use the event
  # timestamp.
  # E.g.: path => "./test-%{+YYYY-MM-dd}.txt" to create 
  # ./test-2013-05-29.txt 
  config :path, :validate => :string, :required => true

  # The maximum size of file to write in bytes. When the file exceeds this
  # threshold, it will be rotated to the current filename + ".N"
  # N starts with 1, if that file already exists, N will shift to 2
  # and so forth.
  # Supports suffix of k, m, or g for kilobyte, megabyte, gigabyte
  #
  config :max_size, :validate => :string

  # The format to use when writing events to the file. This value
  # supports any string and can include %{name} and other dynamic
  # strings.
  #
  # If this setting is omitted, the full json representation of the
  # event will be written as a single line.
  config :message_format, :validate => :string

  # Flush interval (in seconds) for flushing writes to log files. 
  # 0 will flush on every message.
  config :flush_interval, :validate => :number, :default => 2

  # Gzip the output stream before writing to disk.
  config :gzip, :validate => :boolean, :default => false

  public
  def register
    require "fileutils" # For mkdir_p

    workers_not_supported

    @files = {}
    now = Time.now
    @last_flush_cycle = now
    @last_stale_cleanup_cycle = now
    flush_interval = @flush_interval.to_i
    @stale_cleanup_interval = 10

    if @max_size
      @rotate_size = tobytes(@max_size)
      # if string is invalid in some way disable rotation
      # (TODO: should there be a minimum size allowed?)
      @max_size = false unless @rotate_size and @rotate_size.is_a? Integer
    end
  end # def register

  public
  def receive(event)
    return unless output?(event)

    path = event.sprintf(@path)
    
    # Check if we should rotate the file.
    if @max_size
      rotate(path)
    end

    # open after rotate in the event it was moved or closed above
    fd = open(path)

    if @message_format
      output = event.sprintf(@message_format)
    else
      output = event.to_json
    end

    fd.write(output)
    fd.write("\n")

    flush(fd)
    close_stale_files
  end # def receive

  def rotate(path)
    begin
      stat = File.stat(path)
    rescue Errno::ENOENT
      @logger.debug("Path does not exist during rotate: #{path}")
      return
    end

    return unless stat
    return if stat.size < @rotate_size

    i = 0
    # just incase something weird is going on, don't loop forever
    while i < 1000000
      i += 1
      break unless File.exists?(path + ".#{i}")
    end

    begin
      File.rename(path, path + ".#{i}")
    rescue
      @logger.warn("Failed to rotate #{path} to #{path}.#{i}")
      return
    end
    begin
      @files[path].close
    rescue
      @logger.warn("Failed to close #{path}")
    end
    @files.delete(path)
  
  end

  def tobytes(s)
    last = s[-1].downcase
    return s unless ['k','m','g'].include?(last) 

    if last == 'k'
      return s[0..-2].to_i * 1024
    elsif last == 'm'
      return s[0..-2].to_i * 1024 * 1024
    elsif last == 'g'
      return s[0..-2].to_i * 1024 * 1024 * 1024
    end
  end

  def teardown
    @logger.debug("Teardown: closing files")
    @files.each do |path, fd|
      begin
        fd.close
        @logger.debug("Closed file #{path}", :fd => fd)
      rescue Exception => e
        @logger.error("Excpetion while flushing and closing files.", :exception => e)
      end
    end
    finished
  end

  private
  def flush(fd)
    if flush_interval > 0
      flush_pending_files
    else
      fd.flush
    end
  end

  # every flush_interval seconds or so (triggered by events, but if there are no events there's no point flushing files anyway)
  def flush_pending_files
    return unless Time.now - @last_flush_cycle >= flush_interval
    @logger.debug("Starting flush cycle")
    @files.each do |path, fd|
      @logger.debug("Flushing file", :path => path, :fd => fd)
      fd.flush
    end
    @last_flush_cycle = Time.now
  end

  # every 10 seconds or so (triggered by events, but if there are no events there's no point closing files anyway)
  def close_stale_files
    now = Time.now
    return unless now - @last_stale_cleanup_cycle >= @stale_cleanup_interval
    @logger.info("Starting stale files cleanup cycle", :files => @files)
    inactive_files = @files.select { |path, fd| not fd.active }
    @logger.debug("%d stale files found" % inactive_files.count, :inactive_files => inactive_files)
    inactive_files.each do |path, fd|
      @logger.info("Closing file %s" % path)
      fd.close
      @files.delete(path)
    end
    # mark all files as inactive, a call to write will mark them as active again
    @files.each { |path, fd| fd.active = false }
    @last_stale_cleanup_cycle = now
  end

  def open(path)
    return @files[path] if @files.include?(path) and not @files[path].nil?

    @logger.info("Opening file", :path => path)

    dir = File.dirname(path)
    if !Dir.exists?(dir)
      @logger.info("Creating directory", :directory => dir)
      FileUtils.mkdir_p(dir) 
    end

    # work around a bug opening fifos (bug JRUBY-6280)
    stat = File.stat(path) rescue nil
    if stat and stat.ftype == "fifo" and RUBY_PLATFORM == "java"
      fd = java.io.FileWriter.new(java.io.File.new(path))
    else
      fd = File.new(path, "a")
    end
    if gzip
      fd = Zlib::GzipWriter.new(fd)
    end
    @files[path] = IOWriter.new(fd)
  end
end # class LogStash::Outputs::File

# wrapper class
class IOWriter
  def initialize(io)
    @io = io
  end
  def write(*args)
    @io.write(*args)
    @active = true
  end
  def flush
    @io.flush
    if @io.class == Zlib::GzipWriter
      @io.to_io.flush
    end
  end
  def method_missing(method_name, *args, &block)
    if @io.respond_to?(method_name)
      @io.send(method_name, *args, &block)
    else
      super
    end
  end
  attr_accessor :active
end
