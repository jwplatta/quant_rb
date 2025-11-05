FROM ruby:3.2.2

WORKDIR /app

COPY Gemfile Gemfile.lock ./

RUN gem install bundler && bundle install

COPY . /app

RUN mkdir -p /app/logs /app/trades /app/.schwab_rb

CMD ["bundle", "exec", "ruby", "bots/spx_1dte_bot.rb"]