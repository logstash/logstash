require "logstash/outputs/base"
require "logstash/namespace"

# Write events to a 0MQ PUB socket.
#
# You need to have the 0mq 2.1.x library installed to be able to use
# this input plugin.
#
# The default settings will create a publisher connecting to a subscriber
# bound to tcp://127.0.0.1:2120
#
class LogStash::Outputs::ZeroMQ < LogStash::Outputs::Base

  config_name "zeromq"
  plugin_status "experimental"

  # 0mq socket address to connect or bind
  # Please note that `inproc://` will not work with logstash
  # As each we use a context per thread
  # By default, inputs bind/listen
  # and outputs connect
  config :address, :validate => :array, :default => ["tcp://127.0.0.1:2120"]

  # 0mq topology
  # The default logstash topologies work as follows:
  # * pushpull - inputs are pull, outputs are push
  # * pubsub - inputs are subscribers, outputs are publishers
  # * pair - inputs are clients, inputs are servers
  #
  # If the predefined topology flows don't work for you,
  # you can change the 'mode' setting
  # TODO (lusis) add req/rep MAYBE
  # TODO (lusis) add router/dealer
  config :topology, :validate => ["pushpull", "pubsub", "pair"]

  # mode
  # server mode binds/listens
  # client mode connects
  config :mode, :validate => ["server", "client"], :default => "client"

  # 0mq socket options
  # This exposes zmq_setsockopt
  # for advanced tuning
  # see http://api.zeromq.org/2-1:zmq-setsockopt for details
  #
  # This is where you would set values like:
  # ZMQ::HWM - high water mark
  # ZMQ::IDENTITY - named queues
  # ZMQ::SWAP_SIZE - space for disk overflow
  # ZMQ::SUBSCRIBE - topic filters for pubsub
  #
  # example: sockopt => ["ZMQ::HWM", 50, "ZMQ::IDENTITY", "my_named_queue"]
  config :sockopt, :validate => :hash

  # Message output fomart, an sprintf string. If ommited json_event will be used.
  # example: message_format => "%{@timestamp} %{@message}"
  config :message_format, :validate => :string

  public
  def register
    require "ffi-rzmq"
    require "logstash/util/zeromq"
    self.class.send(:include, LogStash::Util::ZeroMQ)

    # Translate topology shorthand to socket types
    case @topology
    when "pair"
      @zmq_const = ZMQ::PAIR
    when "pushpull"
      @zmq_const = ZMQ::PUSH
    when "pubsub"
      @zmq_const = ZMQ::PUB
    end # case socket_type

  end # def register

  public
  def teardown
    error_check(@zsocket.close, "while closing the socket")
  end # def teardown

  private
  def server?
    @mode == "server"
  end # def server?

  def topic(e)
    e.sprintf(@pubsub_topic)
  end

  public
  def receive(event)
    return unless output?(event)

    # TODO(sissel): Figure out why masterzen has '+ "\n"' here
    #wire_event = event.to_hash.to_json + "\n"
    if @message_format
      wire_event = event.sprintf(@message_format) + "\n"
    else
      wire_event = event.to_json
    end

    begin
      if @topology == "pubsub" and @pubsub_topic and not @sockopt.include? "ZMQ::SUBSCRIBE"
        e_topic = topic(event)
        log.debug("0mq: sending topic string", :topic => e_topic) 
        error_check(@zsocket.send_string(e_topic, ::ZMQ::SNDMORE), "in send_string topic")
      end
      @logger.debug("0mq: sending", :event => wire_event)
      error_check(@zsocket.send_string(wire_event), "in send_string")
    rescue => e
      @logger.warn("0mq output exception", :address => @address, :queue => @queue_name, :exception => e, :backtrace => e.backtrace)
    end
  end # def receive
end # class LogStash::Outputs::ZeroMQ
