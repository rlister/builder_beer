# Builder beer

Builds your docker containers while you relax with a beer.

This is lame: it is just a resque worker than does `docker build` and
`docker push`. It can be triggered from a sinatra webhook. That's it.

## Installation

Make sure you have a docker available
(e.g. https://github.com/boot2docker/boot2docker on OSX).

```sh
git clone https://github.com/rlister/builder_beer
cd builder_beer
bundle exec rackup
curl -i 'http://localhost:9292/build?repo=org/repo:branch&image=index.example.com/repo:branch'
```

Right now builder assumes you have a Dockerfile in your repo.
