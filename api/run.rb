#!/usr/bin/env ruby

# need to require gems used at this level
require 'json'
require 'mysql2'
require 'sequel'

raise 'Requires two parameters: lambda name, and a json event test file: ./run ingest sns.json' if ARGV.size!=2

$debug = true
require_relative "#{Dir.pwd}/#{ARGV[0]}/app.rb"

event  = JSON.parse(File.read("events/#{ARGV[1]}"))

pp lambda_handler(event: event, context: {})

