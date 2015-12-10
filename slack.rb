require 'net/http'
require 'json'

class Builder

  ## color should be :good, :warning, :danger, or a hex value
  def self.notify_slack(message, color = :good)
    uri = URI.parse(ENV['SLACK_WEBHOOK'])

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_PEER

    request = Net::HTTP::Post.new(uri.request_uri)
    request.set_form_data(payload: {
      attachments: [{
        text:      message,
        color:     color.to_s,
        mrkdwn_in: %w[ text ],  #allow link formatting in attachment
      }]
    }.to_json)

    http.request(request)
  end

  def self.notify_webhook(params)
    Resque.logger.info "notify webhook"
    return unless params['notify']
    uri = URI.parse(params['notify'])
    http = Net::HTTP.new(uri.host, uri.port)
    # http.use_ssl = true
    # http.verify_mode = OpenSSL::SSL::VERIFY_PEER
    request = Net::HTTP::Get.new(uri.request_uri)
    http.request(request)
  rescue => e
    Resque.logger.info "webook error: #{e.message}"
  end

end
