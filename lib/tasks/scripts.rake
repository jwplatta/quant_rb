namespace :scripts do
  desc "Check portfolio"
  task :check_portfolio do
    system("bundle exec ruby scripts/check_portfolio.rb")
    puts "✅ Portfolio checked!"
  end
end
