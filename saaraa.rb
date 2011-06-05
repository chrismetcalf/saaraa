#!/usr/bin/env ruby

require 'rubygems'
require 'sinatra'
require 'sinatra/reloader' if development?
require 'json'
require 'uri'
require 'mongo'
require 'mongo_mapper'

configure do
  set :raise_errors, false 
  MongoMapper.database = "saaraa"
end

configure :production do
  set :raise_errors, false
  uri = URI.parse(ENV['MONGOHQ_URL'])
  MongoMapper.connection = Mongo::Connection.from_uri(ENV['MONGOHQ_URL'])
  MongoMapper.database = uri.path.gsub(/^\//, '')
end

class Hash
  def recursively_symbolize_keys!
    self.symbolize_keys!
    self.values.each do |v|
      if v.is_a? Hash
        v.recursively_symbolize_keys!
      elsif v.is_a? Array
        v.recursively_symbolize_keys!
      end
    end
    self
  end
end

class Array
  def recursively_symbolize_keys!
    self.each do |item|
      if item.is_a? Hash
        item.recursively_symbolize_keys!
      elsif item.is_a? Array
        item.recursively_symbolize_keys!
      end
    end
  end
end

class Reporter
  include MongoMapper::Document

  key :email, String, :format => /\A[\w+\-.]+@[a-z\d\-.]+\.[a-z]+\z/i
  key :phone, String, :format => /[0-9\-()+]+/

  many :reports

  validate :email_or_phone
  def email_or_phone
    if email.nil? && phone.nil?
      errors.add(:email, "You must specify an email or a phone number")
      errors.add(:phone, "You must specify an email or a phone number")
    end
  end
end

class Report
  include MongoMapper::Document

  key :captured, Date, :required => true
  key :submitted, Date, :required => true

  key :category, String, :required => true # Eventually validate this
  key :description, String, :required => true

  key :photos, Array

  key :severity, String, :in => ["Green", "Yellow", "Red"]
  key :metadata, Object

  one :location
  belongs_to :reporter

  validate :photos_are_urls
  def photos_are_urls
    photos.each do |photo|
      # TODO: Something not absolutely naieve
      if !photo.match(/^http:\/\//)
        errors.add(:photos, "Not a URL: #{photo}")
      end
    end
  end
end

class Location
  include MongoMapper::Document

  key :latitude, Float
  key :longitude, Float
  key :address, String

  belongs_to :reports
end

get '/' do
  @reports = Report.all
  @reporters = Reporter.all
  erb :index
end

post '/reports' do
  content_type :json
  begin
    data = JSON::parse request.body.read
    data.recursively_symbolize_keys!
  rescue Exception => e
    # Should be more picky about excception handling
    puts "Error parsing: #{e.inspect}"
    return [403, "Error parsing JSON request"]
  end

  begin
    # High-level
    report = Report.new
    report.captured = Time.parse(data[:captured])
    report.submitted = Time.now
    report.category = data[:category]
    report.description = data[:description]
    report.severity = data[:severity]

    # The random metadata hash
    report.metadata = data[:metadata]

    # Location
    report.location = Location.new(data[:location])

    # Photos
    report.photos = data[:photos]

    # Reporter
    report.reporter = Reporter.first(:email => data[:reporter][:email])
    if report.reporter.nil?
      report.reporter = Reporter.new(data[:reporter])
    end

    # Save it!
    report.save!

    return report.to_json(:include => [:location, :reporter])
  rescue MongoMapper::DocumentNotValid => e
    [403, "Report failed validation: #{e.message}"]
  rescue Exception => e
    puts e.inspect
    puts e.backtrace
    [500, "Internal error: #{e.message}"]
  end
end
