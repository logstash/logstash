require "logstash/outputs/base"
require "logstash/namespace"

# A plugin for a newly developed Java/Spring Metrics application
# I didn't really want to code this project but I couldn't find
# a respectable alternative that would also run on any Windows
# machine - which is the problem and why I am not going with Graphite
# and statsd.  This application provides multiple integration options
# so as to make its use under your network requirements possible. 
# This includes a REST option that is always enabled for your use
# in case you want to write a small script to send the occasional 
# metric data. 
#
# Find GraphTastic here : https://github.com/NickPadilla/GraphTastic
class LogStash::Outputs::GraphTastic < LogStash::Outputs::Base
  
  config_name "graphtastic"
  plugin_status "beta"
  
  # options are UDP(fastest - default) - RMI(faster) - REST(fast) - TCP (don't use TCP yet - some problems - errors out)
  config :integration, :validate => :string, :default => "udp"
  
  # if using rest as your end point you need to also provide the application url
  # it defaults to localhost/graphtastic - if you change it make sure you
  # include the context root - graphtastic - or if you changed it make sure it
  # matches what is in the web.xml of the graphtastic application
  config :applicationContext, :validate => :string, :default => "graphtastic"
  
  # metrics hash - you will provide a name for your metric and the metric 
  # data as key value pairs.  so for example:
  #
  # metrics => { "Response" => "%{response}" } 
  #
  # example for the logstash config
  #
  # metrics => [ "Response", "%{response}" ]
  #
  # NOTE: you can also use the dynamic fields for the key value as well as the actual value
  config :metrics, :validate => :hash, :default => {}
  
  # Only handle events with any of these tags. if empty check all events.
  config :tags, :validate => :array, :default => []
   
  # host for the graphtastic server - defaults to 127.0.0.1
  config :host, :validate => :string, :default => "127.0.0.1"
  
  # port for the graphtastic instance - defaults to 1199 for RMI, 1299 for TCP, 1399 for UDP, and 8080 for REST
  config :port, :validate => :number, :default => 0
  
  # ability to override the default ISO8601 timestamp format. 
  # we use your date and convert it to time in mills to send it over
  # so I need to manipulate your timestamp to ensure your metric contains
  # the correct time from your logs. By default we use ISO8601 which I 
  # believe is the default for logstash as well, just in case you log doesn't
  # have a timestamp we will use logstash's.
  config :date_pattern, :validate => :string, :default => LogStash::Time::ISO8601
  
  # number of attempted retry after send error - currently only way to integrate
  # errored transactions - should try and save to a file or later consumption
  # either by graphtastic utility or by this program after connectivity is
  # ensured to be established. 
  config :retries, :validate => :number, :default => 1
  
  # the number of metrics to send to GraphTastic at one time. 
  config :batch_number, :validate => :number, :default => 60
  
  # setting allows you to specify where we save errored transactions
  # this makes the most sense at this point - will need to decide
  # on how we reintegrate these error metrics
  # NOT IMPLEMENTED!
  config :error_file, :validate => :string, :default => ""
  
  public
   def register
     require "java"
     @batch = []
     begin
       if @integration.downcase == "rmi"
         if @port == 0
           @port = 1199
         end
         registry = java.rmi.registry.LocateRegistry.getRegistry(@host, @port);
         @remote = registry.lookup("RmiMetricService")
       elsif @integration.downcase == "rest"
         require "net/http"         
         if @port == 0
           @port = 8080
         end
         @http = Net::HTTP.new(@host, @port)
       end       
       @formatter = java.text.SimpleDateFormat.new(@date_pattern)
       @logger.info("GraphTastic Output Successfully Registered! Using #{@integration} Integration!")
     rescue 
       @logger.error("*******ERROR :  #{$!}")
     end
   end

  public
  def receive(event)
    return unless output?(event)
    # Set Intersection - returns a new array with the items that are the same between the two
    if !@tags.empty? && (event.tags & @tags).size == 0
       # Skip events that have no tags in common with what we were configured
       @logger.debug("No Tags match for GraphTastic Output!")
       return
    end
    @retry = 1
    @logger.debug("Event found for GraphTastic!", :tags => @tags, :event => event)
    timestamp = @formatter.parse(java.lang.String.new(event["timestamp"].fetch(0)))
    @metrics.each do |name, metric|
      send(event.sprintf(name),event.sprintf(metric),timestamp.getTime())
    end
  end
  
  def send(name, metric, timestamp)
    message = name+","+metric+","+timestamp.to_s
    if @batch.length < @batch_number
      @batch.push(message)
    else
      sendMessage()
      
    end    
  end
  
  def sendMessage()
    begin
      if @integration.downcase == "tcp"
        # to correctly read the line we need to ensure we send \r\n at the end of every message.
        if @port == 0
          @port = 1299
        end
        tcpsocket = TCPSocket.open(@host, @port)
        tcpsocket.send(@batch.join(',')+"\r\n", 0)
        tcpsocket.close
        @logger.debug("GraphTastic Sent Message Using TCP : #{@batch.join(',')}")
      elsif @integration.downcase == "rmi"
        @remote.insertMetrics(@batch.join(','))
        @logger.debug("GraphTastic Sent Message Using RMI : #{@batch.join(',')}")    
      elsif @integration.downcase == "udp"
        if @port == 0
          @port = 1399
        end
        udpsocket.send(@batch.join(','), 0, @host, @port)
        @logger.debug("GraphTastic Sent Message Using UDP : #{@batch.join(',')}")
      elsif @integration.downcase == "rest"
        request = Net::HTTP::Put.new("/#{@applicationContext}/addMetric/#{@batch.join(',')}")
        response = @http.request(request)
        @logger.debug("GraphTastic Sent Message Using REST : #{@batch.join(',')}", :response => response.inspect)
        if response == 'ERROR'
          raise 'Error happend when sending metric to GraphTastic using REST!'
        end
      else
        @logger.error("GraphTastic Not Able To Find Correct Integration - Nothing Sent - Integration Type : ", :@integration => @integration)
      end
      @batch.clear
    rescue
      @logger.error("*******ERROR :  #{$!}")
      @logger.info("*******Attempting #{@retry} out of #{@retries}")
      while @retry < @retries
        @retry = @retry + 1
        sendMessage()
      end
    end
  end

  def udpsocket; @socket ||= UDPSocket.new end
  
end
