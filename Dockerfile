FROM rlister/ruby:2.1.6
MAINTAINER Ric Lister, rlister@gmail.com

WORKDIR /app

## help docker cache bundle
ADD ./Gemfile      /app/
ADD ./Gemfile.lock /app/

RUN bundle install --without development test

WORKDIR /app
ADD ./ /app

EXPOSE 9292

ENTRYPOINT [ "bundle", "exec" ]
CMD [ "foreman", "start" ]
