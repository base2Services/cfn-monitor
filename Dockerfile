FROM ruby:2.5-alpine

RUN gem install cfn_monitor

WORKDIR /src

CMD ["cfn_monitor"]
