FROM ruby:2.5-alpine

COPY . /src

WORKDIR /src

RUN bundle install

CMD ["rake","-T"]
