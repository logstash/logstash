require "test_utils"
require "logstash/filters/wmts"

describe LogStash::Filters::Wmts do
  extend LogStash::RSpec

  describe "regular calls logged into Varnish logs (apache combined)" do
    config <<-CONFIG
      filter {
        # First, waiting for varnish log file formats (combined apache logs)
        grok { match => [ "message", "%{COMBINEDAPACHELOG}" ] }
        # Then, parameters 
        # Note: the 'wmts.' prefix should match the configuration of the plugin,
        # e.g if "wmts { 'prefix' => 'gis' }", then you should adapt the grok filter
        # accordingly.
        #
        grok {
          match => [
            "request", 
            "(?<wmts.version>([0-9\.]{5}))\/(?<wmts.layer>([a-z0-9\.-]*))\/default\/(?<wmts.release>([0-9]{8}))\/(?<wmts.reference-system>([0-9]*))\/(?<wmts.zoomlevel>([0-9]*))\/(?<wmts.row>([0-9]*))\/(?<wmts.col>([0-9]*))\.(?<wmts.filetype>([a-zA-Z]*))"]
        }
        wmts { }
      }
    CONFIG

    # regular WMTS query from a varnish log
    sample '127.0.0.1 - - [20/Jan/2014:16:48:28 +0100] "GET http://wmts4.testserver.org/1.0.0/' \
      'mycustomlayer/default/20130213/21781/23/470/561.jpeg HTTP/1.1" 200 2114 ' \
      '"http://localhost/ajaxplorer/" "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36' \
      '(KHTML, like Gecko) Ubuntu Chromium/31.0.1650.63 Chrome/31.0.1650.63 Safari/537.36"' do
        # checks that the query has been successfully parsed  
        # and the geopoint correctly reprojected into wgs:84 
        insist { subject["wmts.version"] } == "1.0.0"
        insist { subject["wmts.layer"] } == "mycustomlayer"
        insist { subject["wmts.release"] } == "20130213"
        insist { subject["wmts.reference-system"] } == "21781"
        insist { subject["wmts.zoomlevel"] } == "23"
        insist { subject["wmts.row"] } == "470"
        insist { subject["wmts.col"] } == "561"
        insist { subject["wmts.filetype"] } == "jpeg"
        insist { subject["wmts.service"] } == "wmts"
        insist { subject["wmts.input_epsg"] } == "epsg:21781"
        insist { subject["wmts.input_x"] } == 707488
        insist { subject["wmts.input_y"] } == 109104
        insist { subject["wmts.input_xy"] } == "707488,109104"
        insist { subject["wmts.output_epsg"] } == "epsg:4326"
        insist { subject["wmts.output_xy"] } == "8.829295858079231,46.12486163053951"
        insist { subject["wmts.output_x"] } == 8.829295858079231
        insist { subject["wmts.output_y"] } == 46.12486163053951
      end

    # query extracted from a varnish log, but not matching a wmts request
    sample '83.77.200.25 - - [23/Jan/2014:06:51:55 +0100] "GET http://map.schweizmobil.ch/api/api.css HTTP/1.1"' \
      ' 200 682 "http://www.schaffhauserland.ch/de/besenbeiz" ' \
      '"Mozilla/5.0 (Windows NT 6.1; WOW64; Trident/7.0; rv:11.0) like Gecko"' do
        insist { subject["tags"] }.include?("_grokparsefailure")
    end

    # query looking like a legit wmts log but actually contains garbage [1]
    # - parameters from the grok filter cannot be cast into integers
    sample '127.0.0.1 - - [20/Jan/2014:16:48:28 +0100] "GET http://wmts4.testserver.org/1.0.0/' \
      'mycustomlayer/default/12345678////.raw HTTP/1.1" 200 2114 ' \
      '"http://localhost//" "ozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36' \
      '(KHTML, like Gecko) Ubuntu Chromium/31.0.1650.63 Chrome/31.0.1650.63 Safari/537.36"' do
         insist { subject['wmts.errmsg'] } == "Bad parameter received from the Grok filter"
    end

    # query looking like a legit wmts log but actually contains garbage
    # * 99999999 is not a valid EPSG code (but still parseable as an integer)
    sample '127.0.0.1 - - [20/Jan/2014:16:48:28 +0100] "GET http://wmts4.testserver.org/1.0.0/' \
      'mycustomlayer/default/20130213/99999999/23/470/561.jpeg HTTP/1.1" 200 2114 ' \
      '"http://localhost//" "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36' \
      '(KHTML, like Gecko) Ubuntu Chromium/31.0.1650.63 Chrome/31.0.1650.63 Safari/537.36"' do
         insist { subject['wmts.errmsg'] } == "Unable to reproject tile coordinates"
    end
  end
end

