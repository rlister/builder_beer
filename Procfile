# redis: redis-server
web: bundle exec rackup
resque: bundle exec rake resque:work QUEUE=* VVERBOSE=1
resque-web: bundle exec resque-web --foreground --no-launch --app-dir log
