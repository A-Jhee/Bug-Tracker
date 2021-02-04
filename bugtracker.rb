require "dotenv/load"
require "sinatra"
require "sinatra/content_for"
require "tilt/erubis"
require "time"
require "securerandom"
require "aws-sdk-s3"
require "bcrypt"

require_relative "database_persistence"

ID_ROLE_DELIMITER = "!"
DEMO_LOGINS = [{id: 1, role: "admin", name: "Admin, Demo"},
              {id: 2, role: "project_manager", name: "Project Manager, Demo"},
              {id: 3, role: "developer", name: "Developer, Demo"},
              {id: 4, role: "quality_assurance", name: "Quality Assurance, Demo"}]

configure do
  enable :sessions
  set :session_secret, ENV.fetch('SESSION_SECRET') { SecureRandom.hex(64) }
  set :erb, :escape_html => true
  set :bucket, ENV["AWS_BUCKET"]
end

configure(:development) do
  require "sinatra/reloader"
  also_reload "database_persistence.rb"
  # set :show_exceptions, :after_handler
end

helpers do
  def encrypt(password)
    BCrypt::Password.create(password)
  end

  def correct_password?(password, hashed_password)
    BCrypt::Password.new(hashed_password) == password
  end

  def login_for_role(demo_role)
    session.clear
    DEMO_LOGINS.each do |login|
      if login[:role] == demo_role
        session.clear
        session[:user_id] = login[:id]
        session[:user_name] = login[:name]
        session[:user_role] = prettify_user_role(login[:role])
      end
    end
  end

  # What: Parses psql's timestamp data type to a more readable format.
  #       Month / Day / Year Hour:Minutes [pm or am]. Drops Seconds.
  def parse_timestamp(sql_timestamp)
    Time.parse(sql_timestamp).strftime("%m/%d/%Y %I:%M %p")
  end

  def error_for_ticket_title(title)
    error_msg = "Ticket title must be between 1 and 100 characters."
    return error_msg unless (1..100).cover? title.size
  end

  def error_for_project_name(project_name)
    if !(1..100).cover? project_name.size
      "Project name must be between 1 and 100 characters."
    elsif @storage.all_projects.any? { |project| project["name"] == project_name }
      "That project name is already in use. A project name must be unique."
    end
  end

  def error_for_description(description)
    error_msg = "Description must be between 1 and 300 characters."
    return error_msg unless (1..300).cover? description.size
  end

  def error_for_comment(comment)
    error_msg = "Comment must be between 1 and 300 characters."
    return error_msg unless (1..300).cover? comment.size
  end

  def prettify_property_name(property_name)
    DatabasePersistence::TICKET_PROPERTY_NAME_CONVERSION[property_name]
  end

  def prettify_user_role(user_role)
    DatabasePersistence::USER_ROLE_CONVERSION[user_role]
  end

  def ticket_priorities
    DatabasePersistence::TICKET_PRIORITY
  end

  def ticket_statuses
    DatabasePersistence::TICKET_STATUS
  end

  def ticket_types
    DatabasePersistence::TICKET_TYPE
  end

  def removal_keys
    DatabasePersistence::UNUSED_TICKET_PROPERTIES_FOR_UPDATE_HISTORY
  end

  def ticket_property_name_conversion
    DatabasePersistence::TICKET_PROPERTY_NAME_CONVERSION
  end

  # What: Returns an array that contains a hash for each row of data returned
  #       by psql database for users assigned to the project.
  #       ex) [{"id"=>"1", "role"=>"admin"}, {"id"=>"3", "role"=>"developer"}]
  def current_assigned_users(project_id)
    @storage.all_users_on_project(project_id).map { |user| user }
  end

  # What: Returns an array of user ids. It accepts the returning object from
  #       the method above: #current_assigned_users.
  # Why:  During user assignments/unassignments, just the user id's are compared
  #       to determine which action to take.
  def user_id_array(user_id_role_arr)
    user_id_role_arr.map { |user| user["id"] }
  end

  # What: Returns a hash containing tickets for a project with two new key:value
  #       pairs that contain developer and submitter names
  # Why:  To make it more readable for the app user, the developer_ids and 
  #       submitter_ids found within ticket info used to retrieve corresponding
  #       user names.
  def tickets_for_project_with_usernames(project_id)
    result = []
    @storage.tickets_for_project(project_id).each do |ticket|
      ticket["developer_name"] = @storage.get_user_name(ticket["developer_id"])
      ticket["submitter_name"] = @storage.get_user_name(ticket["submitter_id"])
      result << ticket
    end
    result
  end

  # What: returns PG::Result objects that contain the 4 major categories
  #       of ticket details.
  #
  # Why:  for the purposes of serial assignment.
  def load_ticket_details(ticket_id)
    # uses helper method "get_histories()" to exchange dev id with dev name.
    return @storage.get_ticket(ticket_id), @storage.get_comments(ticket_id),
            @storage.get_ticket_attachments(ticket_id), get_histories(ticket_id)
  end

  # What: returns PG::Result objects that contain the 4 major categories
  #       of ticket details.
  #
  # Why:  for the purposes of serial assignment.
  def load_names_for_ticket_details(ticket)
    return @storage.get_project_name(ticket["project_id"]),
            @storage.get_user_name(ticket["developer_id"]),
            @storage.get_user_name(ticket["submitter_id"])
  end

  # What: Returns True if any of the values in "new_info_hash" differs
  #       from the values in "current_info_hash".
  # Why:  User may submit a ticket update without any changes
  def update_exists?(new_info_hash, current_info_hash)
    new_info_hash.any? { |k, v| current_info_hash[k] != v }
  end

  # What: Detects which ticket info are updated and returns a new hash
  #       of only the changing info's field name and value as key/value pair
  def get_updates_hash(new_info_hash, current_info_hash)
    # new_info_hash.keys = [ "id", "title", "description", "priority",
    #                         "status", "type", "developer_id" ]
    if update_exists?(new_info_hash, current_info_hash)
      new_info_hash.reject { |k, v| current_info_hash[k] == v }
    else
      nil
    end
  end

  # What: returns a hash with changing ticket property names as keys,
  #       and before update values as values.
  # Why:  This information is required to track the before-update-state
  #       in the ticket history.
  def get_pre_updates_hash(new_info_hash, current_info_hash)
    result = current_info_hash.reject { |k, v| new_info_hash[k] == v }
    # removal_keys is a helper function that retrieves a DatabasePersistence constant
    removal_keys.each { |k| result.delete(k) }
    result
  end

  def get_update_history_arr(pre_updates, updates, user_id, ticket_id)
    pre_updates.map do |k, v|
      [k, v, updates[k], user_id, ticket_id]
    end
  end

  # What: Returns a hash containing all ticket history for a ticket with
  #       developer id and updater id swapped for their names.
  def get_histories(ticket_id)
    @storage.get_ticket_histories(ticket_id).map do |history|
      if history["property"] == "developer_id"
        history["previous_value"] = @storage.get_user_name(history["previous_value"])
        history["current_value"] = @storage.get_user_name(history["current_value"])
      end
      history["user_id"] = @storage.get_user_name(history["user_id"])
      history
    end
  end

  # What: Uploads the file content to S3 with the specified object_key.
  #       Returns boolean true or false.
  def s3_object_uploaded?(object_key, file_content)
    s3_client = Aws::S3::Client.new
    response = s3_client.put_object(
      bucket: settings.bucket,
      key: object_key,
      body: file_content,
      content_type: Rack::Mime.mime_type(File.extname(object_key)),
      content_disposition: "inline; filename=\"#{object_key}\""
    )
    if response.etag
      return true
    else
      return false
    end
  rescue StandardError => e
    session[:error] = "Error uploading object: #{e.message}"
    return false
  end

  # What: Downloads the object specified by object key from S3, and returns it.
  #       If no such object exists or an error happens, returns nil.
  # Why:  To use returning object as condition in flow control
  #       (returns object -> true, returns nil -> false)
  def s3_object_download(object_key)
    result = nil
    begin
      s3_client = Aws::S3::Client.new
      result = s3_client.get_object(bucket: settings.bucket, key: object_key)
    rescue StandardError => e
      session[:error] = "Error getting object: #{e.message}"
    end
    result
  end
end

before do
  if ENV["RACK_ENV"] == "test"
    session[:user_id] = "1"
    session[:user_name] = "DEMO_Admin"
    session[:user_role] = "admin"
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

# -------------USERS---------------------------------------------------------- #
# -------------USERS---------------------------------------------------------- #
# -------------USERS---------------------------------------------------------- #
# -------------USERS---------------------------------------------------------- #
# -------------USERS---------------------------------------------------------- #
# -------------USERS---------------------------------------------------------- #

# VIEW USER REGISTRATION FORM
get "/register" do
  erb :register, layout: :register_layout
end

# POST NEW USER REGISTRATION
post "/register" do
  full_name = "#{params[:first_name]} #{params[:last_name]}"
  email = params[:email]
  username = params[:username]
  password = encrypt(params[:password])

  if @storage.valid_new_user?(username, email)
    error = nil
  else
    error = "That username or email is already in use."
  end

  if error
    session[:error] = error
    erb :register, layout: :register_layout
  else
    user_id = @storage.register_new_user(full_name, username, password, email)

    session.clear
    session[:user_id] = user_id
    session[:user_name] = full_name
    session[:user_role] = prettify_user_role("Unassigned")

    session[:success] = "You are now logged in to your new account, #{full_name}."
    redirect "/dashboard"
  end
end

# VIEW LOG IN FORM
get "/login" do
  erb :login, layout: :register_layout
end

# POST USER LOG IN
post "/login" do
  username = params[:username]
  password = params[:password]

  login = @storage.correct_username?(username)

  if login && correct_password?(password, login["password"])
    error = nil
  else
    error = "Username or password was incorrect."
  end

  if error
    session[:error] = error
    erb :login, layout: :register_layout
  else
    user = @storage.user(login["user_id"])

    session.clear
    session[:user_id] = user["id"]
    session[:user_name] = user["name"]
    session[:user_role] = prettify_user_role(user["role"])

    session[:success] =
      "You are now logged in as #{session[:user_role]}, #{session[:user_name]}."
    redirect "/dashboard"
  end
end

post "/demo_login" do
  demo_role = params[:demo_login_role]
  login_for_role(demo_role)

  session[:success] =
      "You are now logged in as #{session[:user_role]}, #{session[:user_name]}."
  redirect "/dashboard"
end

# LOG OUT USER
get "/logout" do
  session.clear

  session[:success] = "You successfully logged out."
  redirect "/login"
end

# -------------PROJECTS------------------------------------------------------- #
# -------------PROJECTS------------------------------------------------------- #
# -------------PROJECTS------------------------------------------------------- #
# -------------PROJECTS------------------------------------------------------- #
# -------------PROJECTS------------------------------------------------------- #
# -------------PROJECTS------------------------------------------------------- #

# VIEW ALL USER'S ASSIGNED PROJECTS
get "/projects" do
  @projects = @storage.all_projects
  erb :projects, layout: :layout
end

# VIEW NEW PROJECT FORM
get "/projects/new" do
  erb :new_project, layout: :layout
end

# POST A NEW PROJECT
post "/projects/new" do
  @name = params[:name].strip
  @description = params[:description].strip

  error = error_for_project_name(@name) || error_for_description(@description)

  if error
    session[:error] = error
    erb :new_project, layout: :layout
  else
    @storage.create_project(@name, @description)

    # Automatically assigning currently logged in user as this new project's manager.
    # It can either be an admin or a project manager only.
    project_id = @storage.get_project_id(@name)
    @storage.assign_user_to_project(project_id, session[:user_id], session[:user_role])

    session[:success] = "You have successfully submitted a new project."
    redirect "/projects"
  end
end

# VIEW ASSIGN USER TO PROJECT FORM
get "/projects/:id/users" do
  @project = @storage.get_project(params[:id])

  assigned_users = current_assigned_users(params[:id])
  assigned_user_ids = user_id_array(assigned_users)
  
  @users = @storage.all_users.map do |user|
    if assigned_user_ids.include?(user["id"])
      user["assigned?"] = true
    end
    user
  end

  erb :assign_users, layout: :layout
end

# POST USER ASSIGNMENTS
post "/projects/:id/users" do
  project_id = params[:id]

  if params[:assigned_users].nil?
    @storage.unassign_all_users_from_project(project_id)

    session[:success] = "There are no users assigned to this project."
    redirect "/projects/#{project_id}"
  else
    new_assigned_users = params[:assigned_users].map do |user|
      id, role = user.split(ID_ROLE_DELIMITER)
      {"id" => id, "role" => role}
    end
    new_assigned_users_ids = user_id_array(new_assigned_users)

    assigned_users = current_assigned_users(project_id)
    assigned_user_ids = user_id_array(assigned_users)

    new_assignments = new_assigned_users.reject do |user|
      assigned_user_ids.include?(user["id"])
    end

    # Assign new users to project
    new_assignments.each do |new_user|
      @storage.assign_user_to_project(project_id, new_user["id"], new_user["role"])
    end

    unassignments = assigned_user_ids.reject do |user_id|
      new_assigned_users_ids.include?(user_id)
    end

    # Unassign users from project
    unassignments.each do |user_id|
      @storage.unassign_user_from_project(project_id, user_id)
    end

    session[:success] = "You have successfully made new user assignments."
    redirect "/projects/#{project_id}"
  end
end

# VIEW EDIT PROJECT FORM
get "/projects/:id/edit" do
  @project = @storage.get_project(params[:id])
  erb :edit_project, layout: :layout
end

# VIEW PROJECT DETAILS
# includes: name, description, assigned users, and tickets for that project
get "/projects/:id" do
  @project_id = params[:id]
  @project = @storage.get_project(@project_id)
  @assigned_users = @storage.get_assigned_users(@project_id)
  @tickets = tickets_for_project_with_usernames(@project_id)
  erb :project, layout: :layout
end

# POST PROJECT EDITS
# edits name and/or description
post "/projects/:id" do
  @name = params[:name].strip
  @description = params[:description].strip
  project_id = params[:id]

  error = error_for_project_name(@name) || error_for_description(@description)

  if error
    session[:error] = error
    erb :edit_project, layout: :layout
  else
    @storage.update_project(@name, @description, project_id)

    session[:success] = "You have successfully updated the project."
    redirect "/projects/#{project_id}"
  end
end

# -------------TICKETS-------------------------------------------------------- #
# -------------TICKETS-------------------------------------------------------- #
# -------------TICKETS-------------------------------------------------------- #
# -------------TICKETS-------------------------------------------------------- #
# -------------TICKETS-------------------------------------------------------- #
# -------------TICKETS-------------------------------------------------------- #

# VIEW ALL TICKETS FOR USER'S ASSIGNED PROJECTS
# column fields (Title, Project Name, Dev. Assigned, Priority, Type, Created On)
get "/tickets" do
  # FIXME: correct this route to show only the tickets from user's
  #        assigned project
  tickets = @storage.all_tickets

  @unresolved_tickets = tickets.select { |ticket| ticket["status"] != "Resolved" }
  @resolved_tickets = tickets.select { |ticket| ticket["status"] == "Resolved" }

  erb :tickets, layout: :layout
end

# VIEW NEW TICKET FORM
get "/tickets/new/*" do
  # params[:splat] maybe a number indicating project id or left blank
  # returns parameter as an array
  # ex) "tickets/new/12"
  #     params[:splat] = ["12"]
  @splat_id = params[:splat].first

  @types = ticket_types
  @priorities = ticket_priorities

  @projects = @storage.all_projects
  @project_name = @storage.get_project_name(@splat_id) unless @splat_id.empty?

  erb :new_ticket, layout: :layout
end

# POST A NEW TICKET
#
# If making a post request w/ route like so: "/tickets/new/12", then ticket
# creation view is hardcoded with project name (cannot select project).
#
# If making a post request w/o route like so: "/tickets/new/", then ticket
# creation view has a select drop down menu for all projects available.
post "/tickets/new/*" do
  title = params[:title].strip # ticket title REQ
  description = params[:description].strip # ticket description DEFAULT n/a REQ
  
  @types = ticket_types
  @type = params[:type] # ticket type REQ
  
  @priorities = ticket_priorities
  @priority = params[:priority] # ticket priority DEFAULT low
  
  @projects = @storage.all_projects

  # Stores project id select via drop down menu in the event that
  # user fails text input validation (for 'title' and 'description').
  #
  # first time through this route, it'll be nil.
  @project_id = params[:project_id]

  @splat_id = params[:splat].first
  @project_name = @storage.get_project_name(@splat_id) unless @splat_id.empty?

  error = error_for_ticket_title(title) || error_for_description(description)

  if error
    session[:error] = error
    erb :new_ticket, layout: :layout
  else
    # default developer_id to 0, or "Unassigned". project manager must assign dev.
    @storage.create_ticket(
                           'Open',
                            title,
                            description,
                            @type,
                            @priority,
                            session[:user_id],
                            @project_id,
                            0
                          )

    session[:success] = "You have successfully submitted a new ticket."
    redirect "/tickets"
  end
end

# VIEW TICKET DETAILS
# includes: ticket properties, comments, attachments, & update history.
get "/tickets/:id" do
  ticket_id = params[:id]

  @ticket, @comments, @attachments, @histories = load_ticket_details(ticket_id)

  @project_name, @developer_name, @submitter_name =
                                         load_names_for_ticket_details(@ticket)

  erb :ticket, layout: :layout
end

# POST TICKET EDITS
post "/tickets/:id" do
  title = params[:title].strip
  description = params[:description].strip

  ticket_id = params[:id]
  @ticket = @storage.get_ticket(ticket_id)

  @project_name = @storage.get_project_name(@ticket["project_id"])

  @developers = @storage.all_developers
  @developer_id = params[:developer_id]
  
  @priorities = ticket_priorities
  @priority = params[:priority]

  @statuses = ticket_statuses
  @status = params[:status]

  @types = ticket_types
  @type = params[:type]

  error = error_for_ticket_title(title) || error_for_description(description)

  if error
    session[:error] = error
    erb :edit_ticket, layout: :layout
  else
    new_ticket_info = {
                        "id"           => ticket_id,
                        "title"        => title,
                        "description"  => description,
                        "priority"     => @priority,
                        "status"       => @status,
                        "type"         => @type,
                        "developer_id" => @developer_id
                      }

    current_ticket_info = @storage.get_ticket(ticket_id)

    # compares new_ticket_info against current_ticket_info to see if any
    # changes were made.
    #
    # returns a hash of only changing key:value pairs, otherwise nil.
    updates = get_updates_hash(new_ticket_info, current_ticket_info)

    if updates
      # updating the changes to the "tickets" table
      @storage.update_ticket(updates, ticket_id)
      session[:success] = "You have successfully made changes to a ticket."

      # making note of the updates in the "ticket_update_history" table
      pre_updates = get_pre_updates_hash(new_ticket_info, current_ticket_info)
      
      # creates an array of array(s) of parameters to be passed into psql statement w/
      # placeholders. each updating value gets one array of parameters.
      update_history_arr =
        get_update_history_arr(pre_updates, updates, session[:user_id], params[:id])

      @storage.create_ticket_history(update_history_arr)
      redirect "/tickets/#{ticket_id}"
    else
      session[:error] = "You did not make any changes. \
         Make any changes to this ticket, or you can return back to Tickets list."
      redirect "/tickets/#{ticket_id}/edit"
    end
  end
end

# VIEW EDIT TICKET FORM
get "/tickets/:id/edit" do
  @ticket = @storage.get_ticket(params[:id])
  @project_name = @storage.get_project_name(@ticket["project_id"])
  @developers = @storage.all_developers

  @priorities = ticket_priorities
  @statuses = ticket_statuses
  @types = ticket_types

  erb :edit_ticket, layout: :layout
end

# POST TICKET COMMENT
post "/tickets/:id/comment" do
  comment = params[:comment].strip
  ticket_id = params[:id]

  @ticket, @comments, @attachments, @histories = load_ticket_details(ticket_id)

  @project_name, @developer_name, @submitter_name =
                                         load_names_for_ticket_details(@ticket)

  error = error_for_comment(comment)

  if error
    session[:error] = error
    erb :ticket, layout: :layout
  else
    @storage.create_comment(comment, session[:user_id], ticket_id)
    redirect "/tickets/#{ticket_id}"
  end
end

# DELETE A TICKET COMMMENT
post "/tickets/:id/comment/:comment_id/destroy" do
  @storage.delete_comment(params[:comment_id])

  if env["HTTP_X_REQUESTED_WITH"] == "XMLHttpRequest"
    session[:success] = "The ticket comment has been deleted."
    "/tickets/#{params[:id]}"
  else # retained for testing purpose
    session[:success] = "The ticket comment has been deleted."
    redirect "/tickets/#{params[:id]}"
  end
end

# UPLOAD A FILE AS ATTACHMENT TO A TICKET
post "/upload/:id" do
  if params[:file] && (tmpfile = params[:file][:tempfile]) && (object_key = params[:file][:filename])
    if s3_object_uploaded?(object_key, File.read(tmpfile))
      @storage.create_attachment(object_key, session[:user_id], params[:notes], params[:id])
      session[:success] = "'#{object_key}' was attached successfully."
    end
  else
    session[:error] = "There was no file selected for attachment. Please select a file to attach."
  end
  redirect "/tickets/#{params[:id]}"
end



# DOWNLOAD AND RETURN ATTACHMENT FILE TO BE VIEWED ON BROWSER
get "/tickets/:id/:filename" do
  object_key = params[:filename]

  response = s3_object_download(object_key)

  if response
    headers['Content-Type'] = response[:content_type]
    headers['Content-Disposition'] = response[:content_disposition]
    response.body
  end
end

# DELETE A TICKET
post "/tickets/:id/destroy" do
  ticket_id = params[:id]

  @storage.delete_ticket(ticket_id)
  if env["HTTP_X_REQUESTED_WITH"] == "XMLHttpRequest"
    session[:success] = "The ticket has been deleted."
    "/tickets"
  else  # retained for testing purpose
    session[:success] = "The ticket has been deleted."
    redirect "/tickets"
  end
end

error 400..510 do
  "I'm sorry. Cannot handle that request."
end