require "date"
require "logstash/inputs/base"
require "logstash/namespace"
require "socket"

# Read gelf messages as events over the network.
#
# This input is a good choice if you already use graylog2 today.
#
# The main reasoning for this input is to leverage existing GELF
# logging libraries such as the gelf log4j appender
#
class LogStash::Inputs::Gelf < LogStash::Inputs::Base
  config_name "gelf"
  milestone 2

  default :codec, "plain"

  # The address to listen on
  config :host, :validate => :string, :default => "0.0.0.0"

  # The port to listen on. Remember that ports less than 1024 (privileged
  # ports) may require root to use.
  config :port, :validate => :number, :default => 12201

  # Whether or not to remap the gelf message fields to logstash event fields or
  # leave them intact.
  #
  # Default is true
  #
  # Remapping converts the following gelf fields to logstash equivalents:
  #
  # * event.message becomes full_message
  #   if no full_message, use event.message becomes short_message
  #   if no short_message, event.message is the raw json input
  # * host + file to event.source
  config :remap, :validate => :boolean, :default => true

  public
  def initialize(params)
    super
    BasicSocket.do_not_reverse_lookup = true
  end # def initialize

  public
  def register
    require 'gelfd'
    @udp = nil
  end # def register

  public
  def run(output_queue)
    LogStash::Util::set_thread_name("input|gelf")
    begin
      # udp server
      udp_listener(output_queue)
    rescue => e
      @logger.warn("gelf listener died", :exception => e, :backtrace => e.backtrace)
      sleep(5)
      retry
    end # begin
  end # def run

  private
  def udp_listener(output_queue)
    @logger.info("Starting gelf listener", :address => "#{@host}:#{@port}")

    if @udp 
      @udp.close_read
      @udp.close_write
    end

    @udp = UDPSocket.new(Socket::AF_INET)
    @udp.bind(@host, @port)

    loop do
      line, client = @udp.recvfrom(8192)
      # Ruby uri sucks, so don't use it.
      source = "gelf://#{client[3]}/"
      begin
        data = Gelfd::Parser.parse(line)
      rescue => ex
        @logger.warn("Gelfd failed to parse a message skipping", :exception => ex, :backtrace => ex.backtrace)
      end

      # The nil guard is needed to deal with chunked messages.
      # Gelfd::Parser.parse will only return the message when all chunks are
      # completed
      event = LogStash::Event.new(data)
      event["source"] = client[3]
      remap_gelf(event) if @remap
      output_queue << event
    end
  ensure
    if @udp
      @udp.close_read rescue nil
      @udp.close_write rescue nil
    end
  end # def udp_listener

  private
  def remap_gelf(event)
    if event["full_message"]
      event.message = event["full_message"].dup
    elsif event["short_message"]
      event.message = event["short_message"].dup
    end
    if event["host"]
      event.source_host = event["host"]
    end
    if event["file"]
      event.source_path = event["file"]
    end
    event.source = "gelf://#{event["host"]}/#{event["file"]}"
  end # def remap_gelf
end # class LogStash::Inputs::Gelf
