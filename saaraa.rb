#!/usr/bin/env ruby

require 'rubygems'
require 'sinatra'
require 'sinatra/reloader' if development?
require 'open-uri'
require 'json'
require 'erb'

configure :production do
  set :raise_errors, false
end

post '/reports' do
  data = JSON::parse request.body.read
  puts data.inspect
end

get '/reports' do
end
