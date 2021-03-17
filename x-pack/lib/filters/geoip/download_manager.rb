# Copyright Elasticsearch B.V. and/or licensed to Elasticsearch B.V. under one
# or more contributor license agreements. Licensed under the Elastic License;
# you may not use this file except in compliance with the Elastic License.

require "bootstrap/util/compress"
require "logstash/util/loggable"
require_relative "util"
require_relative "database_metadata"
require "logstash-filter-geoip_jars"
require "faraday"
require "json"
require "zlib"
require "stud/try"
require "down"
require "fileutils"

module LogStash module Filters module Geoip class DownloadManager
  include LogStash::Util::Loggable
  include LogStash::Filters::Geoip::Util

  def initialize(database_type, metadata, vendor_path)
    @vendor_path = vendor_path
    @database_type = database_type
    @metadata = metadata
  end

  GEOIP_HOST = "https://geoip.elastic.co".freeze
  GEOIP_PATH = "/v1/database".freeze
  GEOIP_ENDPOINT = "#{GEOIP_HOST}#{GEOIP_PATH}".freeze

  public
  # Check available update and download it. Unzip and validate the file.
  # return [has_update, new_database_path]
  def fetch_database
    has_update, database_info = check_update

    if has_update
      new_database_zip_path, new_database_timestamp = download_database(database_info)
      new_database_path = unzip new_database_zip_path, new_database_timestamp
      assert_database!(new_database_path)
      return [true, new_database_path]
    end

    [false, nil]
  end

  private
  # Call infra endpoint to get md5 of latest database and verify with metadata
  # return [has_update, server db info]
  def check_update
    uuid = get_uuid
    res = rest_client.get("#{GEOIP_ENDPOINT}?key=#{uuid}&elastic_geoip_service_tos=agree")
    logger.debug("check update", :endpoint => GEOIP_ENDPOINT, :response => res.status)

    dbs = JSON.parse(res.body)
    target_db = dbs.select { |db| db['name'].eql?("#{database_name_prefix}.#{GZ_EXTENSION}") }.first
    has_update = @metadata.gz_md5 != target_db['md5_hash']
    logger.info "new database version detected? #{has_update}"

    [has_update, target_db]
  end

  def download_database(server_db)
    Stud.try(3.times) do
      timestamp = (Time.now.to_f * 1000).to_i
      new_database_zip_path = get_file_path("#{database_name_prefix}_#{timestamp}.#{GZ_EXTENSION}")
      Down.download(server_db['url'], destination: new_database_zip_path)
      raise "the new download has wrong checksum" if md5(new_database_zip_path) != server_db['md5_hash']

      logger.debug("new database downloaded in ", :path => new_database_zip_path)
      [new_database_zip_path, timestamp]
    end
  end

  def unzip(zip_path, timestamp)
    new_database_path = get_file_path("#{database_name_prefix}_#{timestamp}.#{DB_EXTENSION}")
    extract_dir = get_file_path("#{database_name_prefix}_#{timestamp}")

    LogStash::Util::Tar.extract(zip_path, extract_dir)

    FileUtils.cp( "#{extract_dir}/#{database_name_prefix}.#{DB_EXTENSION}", new_database_path)
    FileUtils.cp_r(Dir.glob("#{extract_dir}/{COPYRIGHT,LICENSE}.txt"), @vendor_path)
    FileUtils.remove_dir(extract_dir)

    new_database_path
  end

  # Make sure the path has usable database
  def assert_database!(database_path)
    raise "failed to load database #{database_path}" unless org.logstash.filters.geoip.GeoIPFilter.database_valid?(database_path)
  end

  def rest_client
    @client ||= Faraday.new do |conn|
      conn.use Faraday::Response::RaiseError
      conn.adapter :net_http
    end
  end

  def get_uuid
    @uuid ||= ::File.read(::File.join(LogStash::SETTINGS.get("path.data"), "uuid"))
  end
end end end end
