require 'sinatra'
require 'resque'
require './builder'

## simple endpoint as GET /build?repo=org/name:branch&image=...
get '/build' do
  begin
    raise 'missing required param: repo' unless params[:repo]

    match = params[:repo].match(/^(?<org>\S+)\/(?<name>\S+):(?<branch>\S+)/)
    raise 'could not parse repo' unless match

    Resque.enqueue(Builder, {
      org:    match[:org],
      name:   match[:name],
      branch: match[:branch],
      image:  params[:image],
    })
    'ok'
  rescue => e
    status 422
    body e.message
  end
end

## receive a post-receive hook from github
post '/github' do

  if env["HTTP_X_GITHUB_EVENT"] == "push"
    payload = JSON.parse(request.body.read)
    Resque.enqueue(Builder, {
      org:    payload['repository']['organization'],
      name:   payload['repository']['name'],
      branch: payload['ref'].gsub('refs/heads/', ''),
    })
    'ok'
  else
    'ignored'
  end

end

## status check for load-balancers, etc
get '/status' do
  'ok'
end
