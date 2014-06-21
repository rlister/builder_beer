require 'sinatra'
require 'resque'
require './builder'

## simole endpoint as GET /build?repo=org/name:branch&image=...
get '/build' do

  if params[:repo]
    org, name, branch = params[:repo].gsub(/\.git$/, '').split(/[:\/]/)
    Resque.enqueue(Builder, {
      org:    org,
      name:   name,
      branch: branch,
      image:  params[:image],
    })
    'ok'
  else
    status 422
    body 'missing required param: repo'
  end

end

## receive a post-receive hook from github
post '/github' do

  if env["HTTP_X_GITHUB_EVENT"] == "push"
    payload = JSON.parse(request.body.read)
    Resque.enqueue(Builder, {
      org:    payload['repository']['organization'],
      name:   payload['repository']['name'],
      branch: payload['ref'].split('/').last,
    })
    'ok'
  else
    'ignored'
  end

end
