require 'http'
require 'json'
require 'mimemagic'
require 'logger'

logger = Logger.new(STDOUT)
logger.level = Logger::DEBUG
logger.debug("parsing config")
config = JSON.parse(File.read("config.json"))

CURRENT_DIR = File.expand_path(File.dirname(__FILE__))
HELIUM_HOST = config["host"]
HELIUM_API_BASE_URL = "#{HELIUM_HOST}/api/v1"
HELIUM_EMAIL = config["email"]
HELIUM_PASS = config["password"]
MAGPHAN_COMMAND = config["command"]

unless !!HELIUM_HOST && !!HELIUM_EMAIL && !!HELIUM_PASS && !!MAGPHAN_COMMAND
  logger.error("config invalid")
  exit(1)
else
  logger.info("starting processing on HeilumQA host #{HELIUM_HOST}")
end

class Processor

  attr_reader :logger

  def initialize(logger)
    @logger = logger
  end

  def authenticate
    response = HTTP.post("#{HELIUM_API_BASE_URL}/auth", json: { email: HELIUM_EMAIL, password: HELIUM_PASS })
    auth = JSON.parse(response.body)
    auth["auth_token"]
  end

  def auth_headers
    logger.debug("Authenticating")
    auth_token = authenticate
    @headers ||= { 'Authorization' => "Bearer #{auth_token}", 'Accept' => 'application/json' }
  end

  def file_base64(file_path)
    mime_type = MimeMagic.by_path(file_path)
    "data:#{mime_type};base64,#{Base64.encode64(open(file_path) { |io| io.read })}"
  end

  def get_analysis_requests
    logger.info("fetching analysis requests")
    requests = HTTP.get("#{HELIUM_API_BASE_URL}/analysis_requests", headers: auth_headers).parse
    logger.debug("fetched #{requests.count} requests from server")
    requests
  end

  def process_analysis_request(url)
    analysis_request = HTTP.get(url, headers: auth_headers).parse
    files = analysis_request["qa_session_files"].map { |f| [f["file_url"], f["filename"]] }
    key = analysis_request["key"]
    analysis_options_file_url = analysis_request["analysis_options_file_url"]
    specifications_file_url = analysis_request["specifications_file_url"]
    module_files = analysis_request["phantom_module_files"].map { |f| [f["file_url"], f["filename"]] }

    # clean slate
    `rm -rf "requests/#{key}" && mkdir -p "requests/#{key}/results"`
    # download each file
    files.each do |url, filename|
      `cd requests/#{key} && curl -o #{filename} #{HELIUM_HOST}#{url}`
    end

    # download analysis options file
    `cd requests/#{key} && curl -o analysis_options.json && #{HELIUM_HOST}#{analysis_options_file_url}` if !!analysis_options_file_url
    # download specifications file
    `cd requests/#{key} && curl -o specifications.json && #{HELIUM_HOST}#{specifications_file_url}` if !!specifications_file_url
    # download phantom module files
    module_files.each do |url, filename|
      `cd requests/#{key} && curl -o #{filename} #{HELIUM_HOST}#{url}`
    end

    # execute command and wait for it to finish
    `#{MAGPHAN_COMMAND
      .gsub('$SOURCE', "#{CURRENT_DIR}/requests/#{key}")
      .gsub('$DESTINATION', "#{CURRENT_DIR}/requests/#{key}/results")}`

    # upload results
    if File.exists?("requests/#{key}/results/results.json")
      file = File.read("requests/#{key}/results/results.json")
      response_data = JSON.parse(file)

      response_data["groups"].each do |group|
        group["results"].each do |result|
          if result["type"] == "file" && !!result["file_path"]
            result["file_value"] = file_base64(result["file_path"])
            result["original_filename"] = File.basename(result["file_path"])
            result.delete("file_path")
          end
        end
      end

      response = HTTP.post(
        "#{HELIUM_API_BASE_URL}/analysis_requests/#{key}/analysis_responses",
        json: { response_data: response_data },
        headers: auth_headers
      )
    end
  end
end

processor = Processor.new(logger)

while true
  request_urls = processor.get_analysis_requests.collect { |req| req["url"] }
  logger.info("processing #{request_urls.count} requests")
  request_urls.each do |url|
    logger.info("started processing request #{url}")
    processor.process_analysis_request(url)
    logger.info("finished processing request #{url}")
  end
  logger.debug("sleep 10 sec")
  sleep(10)
end
