require 'rubygems'
require 'bundler'

Bundler.require

Dotenv.load
require 'active_record'
require 'google/api_client'
require 'google/api_client/client_secrets'
require 'google/api_client/auth/file_storage'
require 'sinatra/reloader' if development?
require 'logger'
require 'net/https'

require 'better_errors'
require 'rack-mini-profiler'
require_relative 'models/init'
require './email.rb'

run Sinatra::Application
