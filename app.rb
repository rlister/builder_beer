require 'sinatra'
require 'resque'
require './builder'

get '/build' do

  if params[:repo]
    "building #{params[:repo]} to #{params[:image]}"
    Resque.enqueue(Builder, *params.values_at(:repo, :image))
  else
    status 422
    body 'missing required param: repo'
  end

end
