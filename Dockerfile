FROM ruby:2.7-alpine

ARG CFN_MONITOR_VERSION=0.4.5

COPY . /src

WORKDIR /src

RUN apk add --no-cache git && \
    gem build cfn_monitor.gemspec && \
    gem install cfn_monitor-${CFN_MONITOR_VERSION}.gem && \
    rm -rf /src
    
RUN cfndsl -u 9.0.0

CMD cfn_monitor
