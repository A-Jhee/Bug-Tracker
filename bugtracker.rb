require "dotenv/load"
require "sinatra"
require "sinatra/content_for"
require "tilt/erubis"
require "time"
require "securerandom"

require_relative "database_persistence"

configure do
  enable :sessions
  set :session_secret, ENV.fetch('SESSION_SECRET') { SecureRandom.hex(64) }
  set :erb, :escape_html => true
end

configure(:development) do
  require "sinatra/reloader"
  also_reload "database_persistence.rb"
end

helpers do
  def parse_timestamp(sql_timestamp)
    Time.parse(sql_timestamp).strftime("%m/%d/%Y %I:%M %p")
  end

  # Two arguments share the same keys, but may or may not have the same values.
  # Returns True if any of the values in "new_info_hash" differs
  # from the values in "current_info_hash".
  def update_exists?(new_info_hash, current_info_hash)
    new_info_hash.any? { |k,v| current_info_hash[k] != v }
  end

  # Detects which ticket info are updated and returns a new hash
  # of only the changing info's field name and value as key/value pair
  def get_updates_hash(new_info_hash, current_info_hash)
    # new_info_hash.keys = [ "id", "title", "description", "priority", 
    #                         "status", "type", "developer_id" ] 
    if update_exists?(new_info_hash, current_info_hash)
      return new_info_hash.reject { |k, v| current_info_hash[k] == v }
    else
      return nil
    end
  end

  def error_for_ticket_title(title)
    if !(1..100).cover? title.size
      "Ticket title must be between 1 and 100 characters."
    end
  end

  def error_for_project_name(name)
    if !(1..100).cover? name.size
      "Project name must be between 1 and 100 characters."
    elsif @storage.all_projects.any? { |project| project["name"] == name }
      "That project name is already in use. Project name must be unique."
    end
  end

  def error_for_description(description)
    if !(1..100).cover? description.size
      "Ticket description must be between 1 and 300 characters."
    end
  end
end

before do
  session[:user_id] ||= 4
  session[:user_name] ||= "DEMO_QualityAssurance"
  session[:user_role] ||= "quality_assurance"
  if ENV["RACK_ENV"] == "test"
    @storage = DatabasePersistence.new("bugtrack_test")
  else
    @storage = DatabasePersistence.new("bugtrack")
  end
end

after do
  @storage.disconnect
end

get "/" do
  redirect "/dashboard"
end

get "/dashboard" do
  erb :dashboard, layout: :layout
end

get "/projects" do
  @projects = @storage.all_projects
  erb :projects, layout: :layout
end

# Show all tickets in database in a specific column field order
get "/tickets" do
  @tickets = @storage.all_tickets
  erb :tickets, layout: :layout
end

# Render the new ticket form
get "/tickets/new" do
  @types = DatabasePersistence::TICKET_TYPE
  @priorities = DatabasePersistence::TICKET_PRIORITY
  @projects = @storage.all_projects
  erb :new_ticket, layout: :layout
end

# Create a new ticket from the "/projects" view for the specified project
get "/tickets/new/:project_id" do
  @project_name = @storage.get_project_name(params[:project_id])
  erb :new_ticket_with_project_id, layout: :layout
end

# Create a new ticket
post "/tickets" do
  title = params[:title].strip #ticket title REQ
  description = params[:description].strip #ticket description DEFAULT n/a REQ
  
  @types = DatabasePersistence::TICKET_TYPE
  @type = params[:type] #ticket type REQ
  
  @priorities = DatabasePersistence::TICKET_PRIORITY
  @priority = params[:priority] #ticket priority DEFAULT low

  @projects = @storage.all_projects
  @project_id = params[:project_id]

  error = error_for_ticket_title(title) || error_for_description(description)
  if error
    session[:error] = error
    erb :new_ticket, layout: :layout
  else
    # default developer_id to 0, or "Unassigned". project manager must assign dev.
    @storage.create_ticket('Open', title, description, @type,
                            @priority, session[:user_id], @project_id, 0)
    session[:success] = "You have successfully submitted a new ticket."
    redirect "/tickets"
  end
end

# View a single ticket details
get "/tickets/:id" do
  'Unfinished route'
end

# Edit an existing ticket
get "/tickets/:id/edit" do
  @ticket = @storage.get_ticket_info(params[:id])
  @project_name = @storage.get_project_name(@ticket["project_id"])
  @developers = @storage.all_developers
  @priorities = DatabasePersistence::TICKET_PRIORITY
  @statuses = DatabasePersistence::TICKET_STATUS
  @types = DatabasePersistence::TICKET_TYPE

  erb :edit_ticket, layout: :layout
end

# Update an existing ticket
post "/tickets/:id" do
  @ticket = @storage.get_ticket_info(params[:id])
  @project_name = @storage.get_project_name(@ticket["project_id"])
  @developers = @storage.all_developers

  title = params[:title].strip
  description = params[:description].strip

  @types = DatabasePersistence::TICKET_TYPE
  @type = params[:type]
  
  @priorities = DatabasePersistence::TICKET_PRIORITY
  @priority = params[:priority]

  @statuses = DatabasePersistence::TICKET_STATUS
  @status = params[:status]

  error = error_for_ticket_title(title) || error_for_description(description)
  if error
    session[:error] = error
    erb :edit_ticket, layout: :layout
    halt
  end

  new_ticket_info = { "id" => params[:id], "title" => title, 
    "description" => description, "priority" => params[:priority], 
    "status" => params[:status], "type" => params[:type], "developer_id" => params[:developer_id] }

  current_ticket_info = @storage.get_ticket_info(params[:id])

  updates = get_updates_hash(new_ticket_info, current_ticket_info)

  if updates
    @storage.update_ticket(updates, params[:id])
    session[:success] = "You have successfully made changes to a ticket."
    redirect "/tickets"
  else
    session[:error] = "You did not make any changes. Make any changes to this ticket, or you can return back to Tickets list."
    redirect "/tickets/#{params[:id]}/edit"
  end
end