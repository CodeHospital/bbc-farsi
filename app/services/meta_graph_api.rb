# Minimal client for Meta's Graph API (graph.facebook.com), shared by
# WhatsappPoster and InstagramPoster. Authenticates with a bearer header so
# the access token never ends up in a URL, a log line or an error message
# (errors are stored in TelegramPost#error_message, shown on the admin UI).
class MetaGraphApi
  REQUEST_TIMEOUT = 20 # seconds

  class Error < StandardError; end

  def initialize(channel)
    @channel = channel
  end

  def post(path, payload)
    request(:post, path, body: payload.to_json, headers: { "Content-Type" => "application/json" })
  end

  def get(path, query = {})
    request(:get, path, query:)
  end

  private

  def request(http_method, path, **options)
    options[:headers] = (options[:headers] || {}).merge("Authorization" => "Bearer #{@channel.token}")
    response = HTTParty.public_send(http_method, "#{@channel.effective_api_base_url}/#{path}", timeout: REQUEST_TIMEOUT, **options)

    response_payload = response.parsed_response
    return response_payload if response.success? && response_payload.is_a?(Hash) && !response_payload.key?("error")

    error_details = response_payload.is_a?(Hash) ? response_payload["error"] : nil
    error_description = if error_details.is_a?(Hash)
      [ error_details["message"], error_details["error_user_msg"] ].compact.uniq.join(" — ")
    else
      response.body.to_s.truncate(200)
    end
    raise Error, "#{@channel.provider_label} #{path.split('/').last} failed (HTTP #{response.code}): #{error_description}"
  end
end
