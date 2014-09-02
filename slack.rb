require 'net/http'
require 'json'

class Builder

  @team    = ENV.fetch('BUILDER_SLACK_TEAM', nil)
  @channel = ENV.fetch('BUILDER_SLACK_CHANNEL', '#test')
  @name    = ENV.fetch('BUILDER_SLACK_NAME', 'builder')
  @token   = ENV.fetch('BUILDER_SLACK_TOKEN', nil)

  def self.notify_slack(repo, message, ok)
    uri = URI.parse("https://#{@team}.slack.com/services/hooks/incoming-webhook?token=#{@token}")

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_PEER

    ## slack-formatted link to this commit in github
    sha_link = "<http://github.com/#{repo.org}/#{repo.name}/commit/#{repo.sha}|#{repo.sha.slice(0,10)}>"

    request = Net::HTTP::Post.new(uri.request_uri)
    request.set_form_data(payload: {
      username: @name,
      channel:  @channel,
      attachments: [{
        # text:      "build #{build_ok ? 'complete' : 'failed'} for #{repo.name}:#{repo.branch} #{sha_link}",
        text:      "#{message} for #{repo.name}:#{repo.branch} #{sha_link}",
        color:     ok ? 'good' : 'danger',
        mrkdwn_in: %w[ text ],  #allow link formatting in attachment
      }]
    }.to_json)

    response = http.request(request)
  end

end
