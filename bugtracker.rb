require "dotenv/load"
require "sinatra"
require "sinatra/content_for"
require "tilt/erubis"
require "time"
require "securerandom"
require "aws-sdk-s3"

require_relative "database_persistence"

configure do
  enable :sessions
  set :session_secret, ENV.fetch('SESSION_SECRET') { SecureRandom.hex(64) }
  set :erb, :escape_html => true
  set :bucket, ENV["AWS_BUCKET"]
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

  def get_pre_updates_hash(new_info_hash, current_info_hash)
    removal_keys = DatabasePersistence::UNUSED_PROPERTIES_FOR_UPDATE_HISTORY
    result = current_info_hash.reject { |k, v| new_info_hash[k] == v }
    removal_keys.each { |k| result.delete(k) }
    result
  end

  def get_update_history_arr(pre_updates, updates, user_id, ticket_id)
    pre_updates.map do |k, v|
      [ k, v, updates[k], user_id, ticket_id ]
    end
  end

  def get_histories(ticket_id)
    result = @storage.get_ticket_histories(ticket_id).map do |ticket_history|
      collector = {}
      ticket_history.each { |k, v| collector[k] = v }
      collector
    end

    result.each do |history|
      if history["property"] == "developer_id"
        history["previous_value"] = @storage.get_user_name(history["previous_value"])
        history["current_value"] = @storage.get_user_name(history["current_value"])
      end
    end
    
    result
  end

  def prettify_property_name(property_name)
    DatabasePersistence::PROPERTY_NAME_CONVERSION[property_name]
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
    if !(1..300).cover? description.size
      "Ticket description must be between 1 and 300 characters."
    end
  end

  def error_for_comment(comment)
    if !(1..300).cover? comment.size
      "Comment must be between 1 and 300 characters."
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

# Show all tickets in database
# column fields (Title, Project Name, Dev. Assigned, Priority, Type, Created On)
get "/tickets" do
  tickets = @storage.all_tickets
  @unresolved_tickets = tickets.select { |ticket| ticket["status"] != "Resolved" }
  @resolved_tickets = tickets.select { |ticket| ticket["status"] == "Resolved" }
  erb :tickets, layout: :layout
end

# Render the new ticket form
get "/tickets/new/*" do
  @splat_id = params[:splat].first
  @types = DatabasePersistence::TICKET_TYPE
  @priorities = DatabasePersistence::TICKET_PRIORITY
  @projects = @storage.all_projects
  @project_name = @storage.get_project_name(@splat_id) unless @splat_id.empty?
  erb :new_ticket, layout: :layout
end

# Create a new ticket
# If routed with a number like so: "/tickets/new/12", then ticket
# creation view is hardcoded with project name (cannot select project)
# If routed without a number like so : "/tickets/new/", then ticket
# creation view has select drop down menu for all projects available.
post "/tickets/new/*" do
  title = params[:title].strip #ticket title REQ
  description = params[:description].strip #ticket description DEFAULT n/a REQ
  
  @types = DatabasePersistence::TICKET_TYPE
  @type = params[:type] #ticket type REQ
  
  @priorities = DatabasePersistence::TICKET_PRIORITY
  @priority = params[:priority] #ticket priority DEFAULT low

  @projects = @storage.all_projects
  @project_id = params[:project_id]
  @splat_id = params[:splat].first
  @project_name = @storage.get_project_name(@splat_id) unless @splat_id.empty?

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

# View a ticket details
# includes: ticket properties, comments, attachments, update history.
get "/tickets/:id" do
  ticket_id = params[:id]
  @ticket = @storage.get_ticket_info(ticket_id)
  @comments = @storage.get_comments(ticket_id)
  @histories = get_histories(ticket_id)
  @attached_files = @storage.get_ticket_attachments(ticket_id)

  @developer_name = @storage.get_user_name(@ticket["developer_id"])
  @submitter_name = @storage.get_user_name(@ticket["submitter_id"])
  @project_name = @storage.get_project_name(@ticket["project_id"])

  erb :ticket, layout: :layout
end

# Post a ticket comment
post "/tickets/:id/comment" do
  comment = params[:comment].strip
  ticket_id = params[:id]
  @ticket = @storage.get_ticket_info(ticket_id)
  @comments = @storage.get_comments(ticket_id)
  @histories = get_histories(ticket_id)

  @developer_name = @storage.get_user_name(@ticket["developer_id"])
  @submitter_name = @storage.get_user_name(@ticket["submitter_id"])
  @project_name = @storage.get_project_name(@ticket["project_id"])

  error = error_for_comment(comment)
  if error
    session[:error] = error
    erb :ticket, layout: :layout
  else
    @storage.create_comment(comment, session[:user_id], params[:id])
    redirect "/tickets/#{ticket_id}"
  end
end

# Delete a ticket commment
post "/tickets/:id/comment/:comment_id/destroy" do
  @storage.delete_comment(params[:comment_id])
  if env["HTTP_X_REQUESTED_WITH"] == "XMLHttpRequest"
    session[:success] = "The ticket comment has been deleted."
    "/tickets/#{params[:id]}"
  else  # retain for testing purpose
    session[:success] = "The ticket comment has been deleted."
    redirect "/tickets/#{params[:id]}"
  end
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

# Download attachment
get "/tickets/:id/:filename" do
  object_key = params[:filename]
  local_path = "./data/downloads/#{object_key}"
  region = "us-west-2"
  s3_client = Aws::S3::Client.new(region: region)

  s3_client.get_object(
    response_target: local_path,
    bucket: settings.bucket,
    key: object_key
  )

  redirect "/tickets/#{params[:id]}"
end

# Upload a file as attachment to a ticket
post "/upload/:id" do
  if params[:file] && (tmpfile = params[:file][:tempfile]) && (object_key = params[:file][:filename])
    region = "us-west-2"
    s3_client = Aws::S3::Client.new(region: region)
    s3_client.put_object(
      bucket: settings.bucket,
      key: object_key,
      body: File.read(tmpfile)
    )

    @storage.create_attachment(object_key, session[:user_id], params[:notes], params[:id])

    session[:success] = "Object '#{object_key}' was uploaded successfully."
    redirect "/tickets/#{params[:id]}"
  end
end

# Update an existing ticket
post "/tickets/:id" do
  @ticket = @storage.get_ticket_info(params[:id])
  @project_name = @storage.get_project_name(@ticket["project_id"])

  @developers = @storage.all_developers
  @developer_id = params[:developer_id]

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
  else
    new_ticket_info = { "id" => params[:id], "title" => title, 
      "description" => description, "priority" => @priority, 
      "status" => @status, "type" => @type, "developer_id" => @developer_id }

    current_ticket_info = @storage.get_ticket_info(params[:id])

    updates = get_updates_hash(new_ticket_info, current_ticket_info)

    if updates
      # Making the updates to the "tickets" table
      @storage.update_ticket(updates, params[:id])
      session[:success] = "You have successfully made changes to a ticket."

      # Making note of the update history in the "ticket_update_history" table
      pre_updates = get_pre_updates_hash(new_ticket_info, current_ticket_info)
      update_history_arr = get_update_history_arr(pre_updates, updates, session[:user_id], params[:id])
      @storage.create_ticket_history(update_history_arr)
      redirect "/tickets/#{params[:id]}"
    else
      session[:error] = "You did not make any changes. Make any changes to this ticket, or you can return back to Tickets list."
      redirect "/tickets/#{params[:id]}/edit"
    end
  end
end

# Delete a ticket
post "/tickets/:id/destroy" do
  id = params[:id]

  @storage.delete_ticket(id)
  if env["HTTP_X_REQUESTED_WITH"] == "XMLHttpRequest"
    session[:success] = "The ticket has been deleted."
    "/tickets"
  else  # retain for testing purpose
    session[:success] = "The ticket has been deleted."
    redirect "/tickets"
  end
end