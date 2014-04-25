# encoding utf-8
require "date"
require "logstash/codecs/base"
require "logstash/namespace"
require "tempfile"
require "time"

# Read events from the connectd binary protocol over the network via udp.
# See https://collectd.org/wiki/index.php/Binary_protocol
#
# Configuration in your Logstash configuration file can be as simple as:
#     input {
#       udp {
#         port => 28526
#         buffer_size => 1452
#         codec => collectd { }
#       }
#     }
#
# A sample collectd.conf to send to Logstash might be:
#
#     Hostname    "host.example.com"
#     LoadPlugin interface
#     LoadPlugin load
#     LoadPlugin memory
#     LoadPlugin network
#     <Plugin interface>
#         Interface "eth0"
#         IgnoreSelected false
#     </Plugin>
#     <Plugin network>
#         <Server "10.0.0.1" "25826">
#         </Server>
#     </Plugin>
#
# Be sure to replace "10.0.0.1" with the IP of your Logstash instance.
#

class ProtocolError < LogStash::Error; end
class HeaderError < LogStash::Error; end
class EncryptionError < LogStash::Error; end

class LogStash::Codecs::Collectd < LogStash::Codecs::Base
  config_name "collectd"
  milestone 1

  AUTHFILEREGEX = /([^:]+): (.+)/

  PLUGIN_TYPE = 2
  COLLECTD_TYPE = 4
  SIGNATURE_TYPE = 512
  ENCRYPTION_TYPE = 528

  TYPEMAP = {
    0               => "host",
    1               => "@timestamp",
    PLUGIN_TYPE     => "plugin",
    3               => "plugin_instance",
    COLLECTD_TYPE   => "collectd_type",
    5               => "type_instance",
    6               => "values",
    7               => "interval",
    8               => "@timestamp",
    9               => "interval",
    256             => "message",
    257             => "severity",
    SIGNATURE_TYPE  => "signature",
    ENCRYPTION_TYPE => "encryption"
  }

  PLUGIN_TYPE_FIELDS = {
    'host' => true,
    '@timestamp' => true,
  }

  COLLECTD_TYPE_FIELDS = {
    'host' => true,
    '@timestamp' => true, 
    'plugin' => true, 
    'plugin_instance' => true,
  }

  INTERVAL_VALUES_FIELDS = {
    "interval" => true, 
    "values" => true,
  }

  INTERVAL_BASE_FIELDS = {
    'host' => true,
    'collectd_type' => true,
    'plugin' => true, 
    'plugin_instance' => true,
    '@timestamp' => true,
    'type_instance' => true,
  }

  INTERVAL_TYPES = {
    7 => true,
    9 => true,
  }

  SECURITY_NONE = "None"
  SECURITY_SIGN = "Sign"
  SECURITY_ENCR = "Encrypt"

  # File path(s) to collectd types.db to use.
  # The last matching pattern wins if you have identical pattern names in multiple files.
  # If no types.db is provided the included types.db will be used (currently 5.4.0).
  config :typesdb, :validate => :array

  # Prune interval records.  Defaults to true.
  config :prune_intervals, :validate => :boolean, :default => true

  # Security Level. Default is "None". This setting mirrors the setting from the
  # collectd [Network plugin](https://collectd.org/wiki/index.php/Plugin:Network)
  config :security_level, :validate => [SECURITY_NONE, SECURITY_SIGN, SECURITY_ENCR],
    :default => "None"

  # Path to the authentication file. This file should have the same format as
  # the [AuthFile](http://collectd.org/documentation/manpages/collectd.conf.5.shtml#authfile_filename)
  # in collectd. You only need to set this option if the security_level is set to
  # "Sign" or "Encrypt"
  config :authfile, :validate => :string

  public
  def register
    @logger.info("Starting Collectd codec...")
    if @typesdb.nil?
      if File.exists?("types.db")
        @typesdb = ["types.db"]
      elsif File.exists?("vendor/collectd/types.db")
        @typesdb = ["vendor/collectd/types.db"]
      else
        raise LogStash::ConfigurationError, "You must specify 'typesdb => ...' in your collectd input"
      end
    end
    @logger.info("Using internal types.db", :typesdb => @typesdb.to_s)
    @types = get_types(@typesdb)

    if ([SECURITY_SIGN, SECURITY_ENCR].include?(@security_level))
      if @authfile.nil?
        raise "Security level is set to #{@security_level}, but no authfile was configured"
      else
        # Load OpenSSL and instantiate Digest and Crypto functions
        require 'openssl'
        @sha256 = OpenSSL::Digest::Digest.new('sha256')
        @sha1 = OpenSSL::Digest::Digest.new('sha1')
        @cipher = OpenSSL::Cipher.new('AES-256-OFB')
        @auth = {}
        parse_authfile
      end
    end
  end # def register

  public
  def get_types(paths)
    types = {}
    # Get the typesdb
    paths.each do |path|
      @logger.info("Getting Collectd typesdb info", :typesdb => path.to_s)
      File.open(path, 'r').each_line do |line|
        typename, *line = line.strip.split
        @logger.debug("typename", :typename => typename.to_s)
        next if typename.nil? || typename[0,1] == '#'
        types[typename] = line.collect { |l| l.strip.split(":")[0] }
      end
    end
    @logger.debug("Collectd Types", :types => types.to_s)
    return types
  end # def get_types

  # Lambdas for hash + closure methodology
  # This replaces when statements for fixed values and is much faster
  string_decoder = lambda { |body| body.pack("C*")[0..-2] }
  numeric_decoder = lambda { |body| body.slice!(0..7).pack("C*").unpack("E")[0] }
  counter_decoder = lambda { |body| body.slice!(0..7).pack("C*").unpack("Q>")[0] }
  gauge_decoder   = lambda { |body| body.slice!(0..7).pack("C*").unpack("E")[0] }
  derive_decoder  = lambda { |body| body.slice!(0..7).pack("C*").unpack("q>")[0] }
  # For Low-Resolution time
  time_decoder = lambda do |body|
    byte1, byte2 = body.pack("C*").unpack("NN")
    Time.at(( ((byte1 << 32) + byte2))).utc
  end
  # Hi-Resolution time
  hirestime_decoder = lambda do |body|
    byte1, byte2 = body.pack("C*").unpack("NN")
    Time.at(( ((byte1 << 32) + byte2) * (2**-30) )).utc
  end
  # Hi resolution intervals
  hiresinterval_decoder = lambda do |body|
    byte1, byte2 = body.pack("C*").unpack("NN")
    Time.at(( ((byte1 << 32) + byte2) * (2**-30) )).to_i
  end
  # Values decoder
  values_decoder = lambda do |body|
    body.slice!(0..1)       # Prune the header
    if body.length % 9 == 0 # Should be 9 fields
      count = 0
      retval = []
      # Iterate through and take a slice each time
      types = body.slice!(0..((body.length/9)-1))
      while body.length > 0
        # Use another hash + closure here...
        retval << VALUES_DECODER[types[count]].call(body)
        count += 1
      end
    else
      @logger.error("Incorrect number of data fields for collectd record", :body => body.to_s)
    end
    return retval
  end
  # Signature
  signature_decoder = lambda do |body|
    if body.length < 32
      @logger.warning("SHA256 signature too small (got #{body.length} bytes instead of 32)")
    elsif body.length < 33
      @logger.warning("Received signature without username")
    else
      retval = []
      # Byte 32 till the end contains the username as chars (=unsigned ints)
      retval << body[32..-1].pack('C*')
      # Byte 0 till 31 contain the signature
      retval << body[0..31].pack('C*')
    end
    return retval
  end
  # Encryption
  encryption_decoder = lambda do |body|
    retval = []
    user_length = (body.slice!(0) << 8) + body.slice!(0)
    retval << body.slice!(0..user_length-1).pack('C*') # Username
    retval << body.slice!(0..15).pack('C*')            # IV
    retval << body.pack('C*')
    return retval
  end
  # Lambda Hashes
  ID_DECODER = {
    0 => string_decoder,
    1 => time_decoder,
    2 => string_decoder,
    3 => string_decoder,
    4 => string_decoder,
    5 => string_decoder,
    6 => values_decoder,
    7 => numeric_decoder,
    8 => hirestime_decoder,
    9 => hiresinterval_decoder,
    256 => string_decoder,
    257 => numeric_decoder,
    512 => signature_decoder,
    528 => encryption_decoder
  }
  # TYPE VALUES:
  # 0: COUNTER
  # 1: GAUGE
  # 2: DERIVE
  # 3: ABSOLUTE
  VALUES_DECODER = {
    0 => counter_decoder,
    1 => gauge_decoder,
    2 => derive_decoder,
    3 => counter_decoder
  }

  public
  def get_values(id, body)
    # Use hash + closure/lambda to speed operations
    ID_DECODER[id].call(body)
  end

  private
  def parse_authfile
    # We keep the authfile parsed in memory so we don't have to open the file
    # for every event.
    @logger.debug("Parsing authfile #{@authfile}")
    if !File.exist?(@authfile)
      raise LogStash::ConfigurationError, "The file #{@authfile} was not found"
    end
    @auth.clear
    @authmtime = File.stat(@authfile).mtime
    File.readlines(@authfile).each do |line|
      #line.chomp!
      k,v = line.scan(AUTHFILEREGEX).flatten
      if k && v
        @logger.debug("Added authfile entry '#{k}' with key '#{v}'")
        @auth[k] = v
      else
        @logger.info("Ignoring malformed authfile line '#{line.chomp}'")
      end
    end
  end # def parse_authfile

  private
  def get_key(user)
    return if @authmtime.nil? or @authfile.nil?
    # Validate that our auth data is still up-to-date
    parse_authfile if @authmtime < File.stat(@authfile).mtime
    key = @auth[user]
    @logger.warn("User #{user} is not found in the authfile #{@authfile}") if key.nil?
    return key
  end # def get_key

  private
  def verify_signature(user, signature, payload)
    # The user doesn't care about the security
    return true if @security_level == SECURITY_NONE

    # We probably got and array of ints, pack it!
    payload = payload.pack('C*') if payload.is_a?(Array)

    key = get_key(user)
    return false if key.nil?

    return OpenSSL::HMAC.digest(@sha256, key, user+payload) == signature
  end # def verify_signature

  private
  def decrypt_packet(user, iv, content)
    # Content has to have at least a SHA1 hash (20 bytes), a header (4 bytes) and
    # one byte of data
    return [] if content.length < 26
    content = content.pack('C*') if content.is_a?(Array)
    key = get_key(user)
    if key.nil?
      @logger.debug("Key was nil")
      return []
    end

    # Set the correct state of the cipher instance
    @cipher.decrypt
    @cipher.padding = 0
    @cipher.iv = iv
    @cipher.key = @sha256.digest(key);
    # Decrypt the content
    plaintext = @cipher.update(content) + @cipher.final
    # Reset the state, as adding a new key to an already instantiated state
    # results in an exception
    @cipher.reset

    # The plaintext contains a SHA1 hash as checksum in the first 160 bits
    # (20 octets) of the rest of the data
    hash = plaintext.slice!(0..19)

    if @sha1.digest(plaintext) != hash
      @logger.warn("Unable to decrypt packet, checksum mismatch")
      return []
    end
    return plaintext.unpack('C*')
  end # def decrypt_packet

  public
  def decode(payload)
    payload = payload.bytes.to_a

    collectd = {}
    was_encrypted = false

    while payload.length > 0 do
      typenum = (payload.slice!(0) << 8) + payload.slice!(0)
      # Get the length of the data in this part, but take into account that
      # the header is 4 bytes
      length  = ((payload.slice!(0) << 8) + payload.slice!(0)) - 4
      # Validate that the part length is correct
      raise(HeaderError) if length > payload.length
      
      body = payload.slice!(0..length-1)

      field = TYPEMAP[typenum]
      if field.nil?
        @logger.warn("Unknown typenumber: #{typenum}")
        next
      end

      values = get_values(typenum, body)

      case typenum
      when SIGNATURE_TYPE
        raise(EncryptionError) unless verify_signature(values[0], values[1], payload)
        next
      when ENCRYPTION_TYPE
        payload = decrypt_packet(values[0], values[1], values[2])
        raise(EncryptionError) if payload.empty?
        was_encrypted = true
        next
      when PLUGIN_TYPE
        # We've reached a new plugin, delete everything except for the the host
        # field, because there's only one per packet and the timestamp field,
        # because that one goes in front of the plugin
        collectd.each_key do |k|
          collectd.delete(k) unless PLUGIN_TYPE_FIELDS.has_key?(k)
        end
      when COLLECTD_TYPE
        # We've reached a new type within the plugin section, delete all fields
        # that could have something to do with the previous type (if any)
        collectd.each_key do |k|
          collectd.delete(k) unless COLLECTD_TYPE_FIELDS.has_key?(k)
        end
      end

      raise(EncryptionError) if !was_encrypted and @security_level == SECURITY_ENCR

      # Fill in the fields.
      if values.is_a?(Array)
        if values.length > 1              # Only do this iteration on multi-value arrays
          values.each_with_index do |value, x|
            begin
              type = collectd['collectd_type']
              key = @types[type]
              key_x = key[x]
              # assign
              collectd[key_x] = value
            rescue
              @logger.error("Invalid value for type=#{type.inspect}, key=#{@types[type].inspect}, index=#{x}")
            end
          end
        else                              # Otherwise it's a single value
          collectd['value'] = values[0]      # So name it 'value' accordingly
        end
      elsif field != nil                  # Not an array, make sure it's non-empty
        collectd[field] = values            # Append values to collectd under key field
      end

      if INTERVAL_VALUES_FIELDS.has_key?(field)
        if ((@prune_intervals && !INTERVAL_TYPES.has_key?(typenum)) || !@prune_intervals)
          # Prune these *specific* keys if they exist and are empty.
          # This is better than looping over all keys every time.
          collectd.delete('type_instance') if collectd['type_instance'] == ""
          collectd.delete('plugin_instance') if collectd['plugin_instance'] == ""
          # This ugly little shallow-copy hack keeps the new event from getting munged by the cleanup
          # With pass-by-reference we get hosed (if we pass collectd, then clean it up rapidly, values can disappear)
          yield LogStash::Event.new(collectd.dup)
        end
        # Clean up the event
        collectd.each_key do |k|
          collectd.delete(k) if !INTERVAL_BASE_FIELDS.has_key?(k)
        end
      end
    end # while payload.length > 0 do
  rescue EncryptionError, ProtocolError, HeaderError
    # basically do nothing, we just want out
  end # def decode

end # class LogStash::Codecs::Collectd
