require "test_utils"
require "logstash/outputs/graphite"
require "mocha/api"

describe LogStash::Outputs::Graphite do
  extend LogStash::RSpec

  before :each do
    @mock = StringIO.new
    TCPSocket.expects(:new).with("localhost", 2003).returns(@mock)
  end

  describe "fields_are_metrics => true" do
    describe "metrics_format => ..." do
      describe "match one key" do
        config <<-CONFIG
          input {
            generator {
              message => "foo=123"
              count => 1
              type => "generator"
            }
          }

          filter {
            kv { }
          }

          output {
            graphite {
                host => "localhost"
                port => 2003
                fields_are_metrics => true
                include_metrics => ["foo"]
                metrics_format => "foo.bar.sys.data.*"
                debug => true
            }
          }
        CONFIG

        agent do
          @mock.rewind
          lines = @mock.readlines
          insist { lines.size } == 1
          insist { lines[0] } =~ /^foo.bar.sys.data.foo 123.0 \d{10,}\n$/
        end
      end

      describe "match all keys" do
        config <<-CONFIG
          input {
            generator {
              message => "foo=123 bar=42"
              count => 1
              type => "generator"
            }
          }

          filter {
            kv { }
          }

          output {
            graphite {
                host => "localhost"
                port => 2003
                fields_are_metrics => true
                include_metrics => [".*"]
                metrics_format => "foo.bar.sys.data.*"
                debug => true
            }
          }
        CONFIG

        agent do
          @mock.rewind
          lines = @mock.readlines.delete_if { |l| l =~ /\.sequence \d+/ }

          insist { lines.size } == 2
          insist { lines }.any? { |l| l =~ /^foo.bar.sys.data.foo 123.0 \d{10,}\n$/ }
          insist { lines }.any? { |l| l =~ /^foo.bar.sys.data.bar 42.0 \d{10,}\n$/ }
        end
      end

      describe "no match" do
        config <<-CONFIG
          input {
            generator {
              message => "foo=123 bar=42"
              count => 1
              type => "generator"
            }
          }

          filter {
            kv { }
          }

          output {
            graphite {
              host => "localhost"
              port => 2003
              fields_are_metrics => true
              include_metrics => ["notmatchinganything"]
              metrics_format => "foo.bar.sys.data.*"
              debug => true
            }
          }
        CONFIG

        agent do
          @mock.rewind
          lines = @mock.readlines
          insist { lines.size } == 0
        end
      end

      describe "match one key with invalid metric_format" do
        config <<-CONFIG
          input {
            generator {
              message => "foo=123"
              count => 1
              type => "generator"
            }
          }

          filter {
            kv { }
          }

          output {
            graphite {
                host => "localhost"
                port => 2003
                fields_are_metrics => true
                include_metrics => ["foo"]
                metrics_format => "invalidformat"
                debug => true
            }
          }
        CONFIG

        agent do
          @mock.rewind
          lines = @mock.readlines
          insist { lines.size } == 1
          insist { lines[0] } =~ /^foo 123.0 \d{10,}\n$/
        end
      end
    end
  end

  describe "fields are metrics = false" do
    describe "metrics_format not set" do
      describe "match one key with metrics list" do
        config <<-CONFIG
          input {
            generator {
              message => "foo=123"
              count => 1
              type => "generator"
            }
          }

          filter {
            kv { }
          }

          output {
            graphite {
                host => "localhost"
                port => 2003
                fields_are_metrics => false
                include_metrics => ["foo"]
                metrics => [ "custom.foo", "%{foo}" ]
                debug => true
            }
          }
        CONFIG

        agent do
          @mock.rewind
          lines = @mock.readlines

          insist { lines.size } == 1
          insist { lines[0] } =~ /^custom.foo 123.0 \d{10,}\n$/
        end
      end

    end
  end
end
