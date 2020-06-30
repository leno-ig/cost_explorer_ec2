# build for development
#   docker-compose build ruby 
# options
#   --no-cache
#   --pull


FROM ruby:2.6.3-alpine3.9

COPY . /myapp

WORKDIR /myapp

RUN bundle install -j4

CMD ["irb -I ./lib -r cost_explorer_ec2"]