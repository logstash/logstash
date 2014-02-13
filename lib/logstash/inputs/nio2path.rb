# encoding: utf-8
require "logstash/inputs/base"
require "logstash/namespace"
require "socket" # for Socket.gethostname

# Read events from a Java NIO.2 Path.
#
# By default, each event is assumed to be one line. If you
# want to join lines, you'll want to use the multiline filter.
class LogStash::Inputs::Nio2Path < LogStash::Inputs::Base
  config_name "nio2path"
  milestone 1

  default :codec, "plain"
  
  # The directory to watch for files.  Must be a directory!
  # 
  # This directory will be monitored and any (non-subdirectory) files
  # in it matching the glob <prefix>*<suffix> will be processed.
  config :path, :validate => :string, :required => true
  
  # Prefix on filenames in the watched directory.
  # "access" for example
  config :prefix, :validate => :string, :default => ""

  # Suffix on filenames in the watched directory.
  # ".log" for example
  config :suffix, :validate => :string, :default => ""

  # Choose where Logstash starts initially reading files - at the beginning or
  # at the end. The default behavior treats files like live streams and thus
  # starts at the end. If you have old data you want to import, set this
  # to 'beginning'
  config :start_position, :validate => [ "beginning", "end"], :default => "end"
  
  # Maximum sleep time for polling filesystem changes (milliseconds)
  config :timeout, :validate => :number, :default => 100

  public
  def register
    @host = Socket.gethostname
    @charset = java.nio.charset.Charset.forName("UTF-8")
    @readers = {}
    begin
      uri = java.net.URI.new(@path)
      @javapath = java.nio.file.Paths.get(uri)
    rescue java.lang.IllegalArgumentException => e
      @javapath = java.nio.file.Paths.get(@path)
    rescue java.lang.Exception => e
      e.printStackTrace
      raise e
    end
    begin
      # Get list of files in path using glob
      java.nio.file.Files.newDirectoryStream(@javapath, @prefix + "*" + @suffix).each do |file|
        # Save a reader for each file (non-directory)
        if (!java.nio.file.Files.isDirectory(file))
          @readers[file.getFileName.toString] = java.nio.file.Files.newBufferedReader(file, @charset)
        end
      end
      # Register a filesystem watchservice to monitor changes to files in the path
      @watchservice = @javapath.getFileSystem.newWatchService
    rescue java.lang.Exception => e
      e.printStackTrace
      raise e
    end
    
    # Try to register all three kinds of events with the watch service.
    [java.nio.file.StandardWatchEventKinds::ENTRY_MODIFY,
     java.nio.file.StandardWatchEventKinds::ENTRY_CREATE,
     java.nio.file.StandardWatchEventKinds::ENTRY_DELETE].each do |kind|
      begin
        @javapath.register(@watchservice, kind)
      rescue java.lang.Exception => e
        @logger.warn("Unable to register watcher for event kind " + kind.name +
                         " on path " + @javapath + ". This may not be fatal.")
      end
    end
  end # def register

  def run(queue)
    # Read or skip data in existing files
    @readers.each do |file, rdr|
      absolutepath = @javapath.resolve(file).toAbsolutePath
      begin
        if (@start_position == "end")
          rdr.skip(java.nio.file.Files.size(absolutepath))
        else
          while (rdr.ready)
            @codec.decode(rdr.readLine) do |event|
              decorate(event)
              event["host"] = @host
              event["path"] = absolutepath.toString
              queue << event
            end
          end
        end
      rescue java.lang.Exception => e
        e.printStackTrace
      end
    end
    
    # Watch for new & modified files
    while true
      begin
        # Get new filesystem change events, or sleep
        while (watchkey = @watchservice.poll(@timeout, java.util.concurrent.TimeUnit::MILLISECONDS))
          begin
            watchkey.pollEvents.each do |watchevent|
              p = watchevent.context
              if (p.getFileName.toString.start_with?(@prefix) && p.getFileName.toString.end_with?(@suffix))
                file = @javapath.resolve(p).toAbsolutePath
                
                # If file has been deleted, clear out its reader
                if (!java.nio.file.Files.exists(file))
                  reader = @readers[p.getFileName.toString]
                  if (reader)
                    reader.close
                  end
                  @readers[p.getFileName.toString] = nil
                  
                # Otherwise, file has been created or modified
                elsif (!java.nio.file.Files.isDirectory(file))
                  
                  # Look for an existing reader for the new or modified file
                  reader = @readers[p.getFileName.toString]
                  
                  # If this file was just created, set up a reader for it
                  if (reader.nil?)
                      reader = java.nio.file.Files.newBufferedReader(file, @charset)
                      @readers[p.getFileName.toString] = reader
                  end
                  
                  # Read new lines from file
                  while (reader.ready)
                    @codec.decode(reader.readLine) do |event|
                      decorate(event)
                      event["host"] = @host
                      event["path"] = file.toString
                      queue << event
                    end
                  end
                end
              end
            end
            watchkey.reset
          rescue java.lang.Exception => e
            e.printStackTrace
            raise e
          end

        end
      rescue EOFError, LogStash::ShutdownSignal
        break
      end
    end # while true
    finished
  end # def run

  public
  def teardown
    @watchservice.close
    @logger.debug("nio2path shutting down.")
    finished
  end # def teardown
end # class LogStash::Inputs::Nio2Path
