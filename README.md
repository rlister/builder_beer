# Builder beer

Builds your docker containers while you relax with a beer.

This is lame: it is just a resque worker that clones a repo from
github, does `docker build` and `docker push`. It can be triggered
from a sinatra webhook. That's it.

## Installation

Make sure you have redis and docker available
(e.g. https://github.com/boot2docker/boot2docker on OSX).

```sh
git clone https://github.com/rlister/builder_beer
cd builder_beer
bundle exec foreman start
curl -i 'http://localhost:9292/build?repo=org/repo:branch&image=index.example.com/repo:branch'
```

Right now builder assumes you have a Dockerfile in your repo. This
will be relaxed in later versions.

## Running as a docker container

You will probably want to mount storage for git repos (so full
re-clone is not required after container restart), and point resque at
an external redis instance:

```
docker run -d --name builder \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /data:/data \
  -e BUILDER_HOME=/data \
  -e REDIS_URL=redis://172.17.42.1:6379/0 \
  -e GITHUB_TOKEN=024599c4f72e010b926795198cb73db5f2cfee77 \
  -p 9292:9292 \
  rlister/builder_beer:latest
```

All the usual docker build caveats apply: i.e. give yourself plenty of
storage and cleanup orphaned containers and images on a regular basis.
