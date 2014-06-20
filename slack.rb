require 'net/http'
require 'json'

class Builder

  @team    = ENV.fetch('BUILDER_SLACK_TEAM', nil)
  @channel = ENV.fetch('BUILDER_SLACK_CHANNEL', '#test')
  @name    = ENV.fetch('BUILDER_SLACK_NAME', 'builder')
  @token   = ENV.fetch('BUILDER_SLACK_TOKEN', nil)

  def self.notify_slack(repo, build_ok)
    uri = URI.parse("https://#{@team}.slack.com/services/hooks/incoming-webhook?token=#{@token}")

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_PEER

    request = Net::HTTP::Post.new(uri.request_uri)
    request.set_form_data(payload: {
      username: @name,
      channel:  @channel,
      attachments: [{
        text:      "build #{build_ok ? 'complete' : 'failed'} for #{repo.name}:#{repo.branch} #{repo.sha.slice!(0,10)}",
        color:     build_ok ? 'good' : 'danger',
      }]
    }.to_json)

    response = http.request(request)
  end

end
