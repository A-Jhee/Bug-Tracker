require "dotenv/load"
require "sinatra"
require "sinatra/content_for"
require "tilt/erubis"

require_relative "database_persistence"

configure do
  set :erb, escape_html: true
end

configure(:development) do
  require "sinatra/reloader"
  also_reload "database_persistence.rb"
end

# helpers

before do
  @storage = DatabasePersistence.new(logger)
end

after do
  @storage.disconnect
end

get "/" do
  redirect "/Dashboard"
end

get "/Dashboard" do
  erb :dashboard, layout: :layout
end

get "/Projects" do
  @projects = @storage.all_projects
  erb :projects, layout: :layout
end