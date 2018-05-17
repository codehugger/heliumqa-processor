require 'http'
require 'json'
require 'mimemagic'

HELIUM_HOST = 'http://localhost:3000'
HELIUM_API_BASE_URL = "#{HELIUM_HOST}/api/v1"
HELIUM_EMAIL = 'user@example.com'
HELIUM_PASS = 'password'

def authenticate(email, password)
  response = HTTP.post("#{HELIUM_API_BASE_URL}/auth", json: { email: email, password: password })
  auth = JSON.parse(response.body)
  auth["auth_token"]
end

def auth_headers
  auth_token = authenticate(HELIUM_EMAIL, HELIUM_PASS)
  headers = { 'Authorization' => "Bearer #{auth_token}", 'Accept' => 'application/json' }
end

def file_base64(file_path)
  mime_type = MimeMagic.by_path(file_path)
  "data:#{mime_type};base64,#{Base64.encode64(open(file_path) { |io| io.read })}"
end

def get_analysis_requests
  HTTP.get("#{HELIUM_API_BASE_URL}/analysis_requests", headers: auth_headers).parse
end

def process_analysis_request(url)
  analysis_request = HTTP.get(url, headers: auth_headers).parse
  files = analysis_request["qa_session_files"].map { |f| [f["file_url"], f["filename"]] }
  key = analysis_request["key"]

  # clean slate
  `rm -rf "requests/#{key}" && mkdir -p "requests/#{key}"`
  # download each file
  files.each do |url, filename|
    `cd requests/#{key} && curl -o #{filename} #{HELIUM_HOST}#{url}`
  end

  # execute dummy script and wait for it to finish
  `perl dummy.pl "requests/#{key}"`

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

while true
  request_urls = get_analysis_requests.collect { |req| req["url"] }
  request_urls.each do |url|
    process_analysis_request(url)
  end
  sleep(10)
end
