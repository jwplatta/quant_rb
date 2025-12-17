#!/bin/bash
set -e

echo "=== Deployment started at $(date) ==="

cd ~/options_trader

echo "Pulling latest code..."
git pull origin main

echo "Installing dependencies..."
bundle install

echo "Running tests..."
cd bots
echo $(pwd)

bundle exec rspec

echo "Stopping old bot process..."
pkill -f spx_1dte.rb || true
sleep 2

cd ..
echo $(pwd)
echo "Starting bot..."
nohup bundle exec ruby bots/spx_1dte.rb >> ~/.options_trader/logs/nohup_spx_1dte.log 2>&1 &

echo "Bot deployed! PID: $!"
echo "Check logs: tail -f ~/.options_trader/logs/bot.log"

echo "=== Deployment finished at $(date) ==="