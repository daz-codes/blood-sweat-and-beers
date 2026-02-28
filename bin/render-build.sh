#!/usr/bin/env bash

set -o errexit

bundle install
bin/rails assets:precompile
bin/rails assets:clean

bin/rails db:migrate
bin/rails db:migrate:cache
bin/rails db:migrate:queue
bin/rails db:migrate:cable
