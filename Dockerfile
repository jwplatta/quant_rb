FROM ruby:3.2.2

WORKDIR /app

COPY . /app

RUN gem install bundler && bundle install

CMD ["bundle", "exec", "clockwork", "bin/spx_opt_chain_download_job.rb"]