require 'sinatra'
require 'resque'
require 'json'
require './builder'

## simple endpoint as GET /build?repo=org/name:branch&image=...
get '/build' do
  begin
    raise 'missing required param: repo' unless params[:repo]

    match = params[:repo].match(/^(?<org>\S+)\/(?<name>\S+):(?<branch>\S+)/)
    raise "could not parse repo <#{params[:repo]}>" unless match

    Resque.enqueue(Builder, {
      org:    match[:org],
      name:   match[:name],
      branch: match[:branch],
      image:  params[:image],
      commit: params[:commit],
      notify: params[:notify],
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
    if payload['ref'].match(/^refs\/tags\//)
      'tag commit: ignored'
    else
      Resque.enqueue(Builder, {
        org:    payload['repository']['organization'],
        name:   payload['repository']['name'],
        branch: payload['ref'].gsub('refs/heads/', ''),
      })
      'ok'
    end
  else
    'not a push: ignored'
  end
end

## status check for load-balancers, etc
get '/status' do
  'ok'
end

## get queue lengths and next job
get '/status/queues' do
  Resque.queues.each_with_object({}) do |q, hash|
    hash[q] = {
      size: Resque.size(q),
      peek: Resque.peek(q),
    }
  end.to_json
end

## show working jobs
get '/status/jobs' do
  Resque.working.map do |worker|
    worker.job.merge(id: worker.id)
  end.to_json
end

## delete a (stuck) worker by id (first matching)
delete '/status/jobs/:id' do
  worker = Resque.working.find do |w|
    w.id.match(/#{params[:id]}/)
  end
  worker.unregister_worker if worker
end

## show most recent failures
get '/status/failures' do
  count = params.fetch('last', 1).to_i
  Resque::Failure.all(-1*count, count).to_json
end
