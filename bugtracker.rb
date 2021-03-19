require 'dotenv/load'
require 'sinatra'
require 'sinatra/content_for'
require 'sinatra/reloader' if development?
require 'tilt/erubis'
require 'time'
require 'securerandom'
require 'aws-sdk-s3'
require 'bcrypt'
require 'date'
require 'pg'

require_relative 'models/ticket'

ID_ROLE_DELIMITER = '!'

DEMO_LOGINS = [{id: '1', role: 'admin'},
              {id: '2', role: 'project_manager'},
              {id: '3', role: 'developer'},
              {id: '4', role: 'quality_assurance'}]

PSQL_ROLE_LOGINS =
  {
    'admin' => ENV['DB_ADMIN_PASSWORD'],
    'project_manager' => ENV['DB_PM_PASSWORD'],
    'developer' => ENV['DB_DEV_PASSWORD'],
    'quality_assurance' => ENV['DB_QA_PASSWORD']
  }

configure do
  enable :sessions
  set :session_secret, ENV.fetch('SESSION_SECRET') { SecureRandom.hex(64) }
  set :erb, :escape_html => true
  set :bucket, ENV['AWS_BUCKET']
  # set :show_exceptions, false
end

configure(:development) do
  require 'sinatra/reloader'
  also_reload 'models/ticket.rb'
  # set :show_exceptions, :after_handler
end

# -------------HELPER METHODS------------------------------------------------- #
# -------------HELPER METHODS------------------------------------------------- #
# -------------HELPER METHODS------------------------------------------------- #
# -------------HELPER METHODS------------------------------------------------- #
# -------------HELPER METHODS------------------------------------------------- #
# -------------HELPER METHODS------------------------------------------------- #

helpers do

  ## params
  #  -url:   heroku psql DATABASE_URL
  ## purpose
  #  -Parses heroku postgres DATABASE_URL environment variable to a string
  ## return value
  #  -string that can be directly passed into PG#connect for db connection
  def database_url(url)
    _, _, tokens, dbname = url.split('/')
    user, tokens, port = tokens.split(':')
    password, host = tokens.split('@')
    "dbname=#{dbname} host=#{host} port=#{port} " +
    "user=#{user} password=#{password} sslmode=require"
  end

  ## params
  #  -url:   heroku psql DATABASE_URL
  ## purpose
  #  -Parses psql's timestamp data type to a more readable format.
  #   Month / Day / Year Hour:Minutes [pm or am]. Drops Seconds.
  ## return value
  #  -formatted string (ex. "01/23/2021 12:40 PM")
  def parse_timestamp(sql_timestamp)
    Time.parse(sql_timestamp).strftime("%m/%d/%Y %I:%M %p")
  end

  ## params
  #  -password:   raw password as string
  ## purpose
  #  -uses BCrypt to hash raw password to prep for secure storage.
  ## return value
  #  -BCrypt hashed password as string
  def encrypt(password)
    BCrypt::Password.create(password)
  end

  ## params
  #  -password:        raw password as string
  #  -hashed_password: hashed password from db as string
  ## purpose
  #  -checks to see if given password matches password in database
  ## return value
  #  -true or false
  def correct_password?(password, hashed_password)
    BCrypt::Password.new(hashed_password) == password
  end

  ## params
  #  -demo_role:   user role as string
  ## purpose
  #  -uses role to login for a demo user
  ## return value
  #  -not used
  def login_for_role(demo_role)
    DEMO_LOGINS.each do |login|
      if login[:role] == demo_role
        session.clear
        session[:user] = User.new(@db, login[:id])
      end
    end
  end

  ## return value
  #  -User class instance stored in session or nil
  def user_authorized?
    session[:user]
  end

  ## purpose
  #  -check to see if user is logged in, and if so if that user is
  #   either a project manager or an admin
  def pm_authorized?
    role = session[:user].role

    user_authorized? && (role == 'project_manager' || role == 'admin')
  end

  ## purpose
  #  -check to see if user is logged in, and if so if that user is an admin
  def admin_authorized?
    role = session[:user].role

    user_authorized? && (role == 'admin')
  end

  ## purpose
  #  -requires a user to be logged-in before visiting any routes in the app
  def require_signed_in_user
    unless user_authorized?
      session[:error] = 'You must be logged in to do that'
      redirect '/login'
    end
  end

  ## purpose
  #  -requires a logged-in user to be project manager
  def required_signed_in_pm
    require_signed_in_user

    unless pm_authorized?
      session[:error] = 'You are not authorized for that action'
      redirect '/dashboard'
    end
  end

  ## purpose
  #  -requires a logged-in user to be admin
  def required_signed_in_admin
    require_signed_in_user

    unless admin_authorized?
      session[:error] = 'You are not authorized for that action'
      redirect '/dashboard'
    end
  end

  ## params
  #  -project_name:   string
  ## purpose
  #  -checks if given project name is alreayd existing in database or not
  ## return value
  #  -error message as string or nil
  def error_for(project_name)
    if Project.all(@db).any? { |project| project['name'] == project_name }
      'That project name is already in use. A project name must be unique.'
    else
      nil
    end
  end

  ## params
  #  -project_ids:   array of project id as string or int
  #                  ex. ['2', '3', '5', 9']
  ## purpose
  #  -returns Project class instance object for each project id found in
  #   the project_ids array
  ## return value
  #  -array of Project class instance objects
  def projects(project_ids)
    project_ids.map do |project_id|
      Project.new(@db, project_id)
    end
  end

  ## params
  #  -project_ids:   array of project id as string or int
  #                  ex. ['2', '3', '5', 9']
  ## purpose
  #  -returns project details for each given project id in the argument array
  ## return value
  #  -an array of hashes. Each array elements are project details
  #   for the '/projects' view for each of the project id in the argument
  def all_details_for(project_ids)
    result =[]
    project_ids.each do |project_id|
      result << Project.details(@db, project_id)
    end
    result.sort { |a, b| a['name'].upcase <=> b['name'].upcase }
  end

  def prettify_property_name(property_name)
    Ticket::TICKET_PROPERTY_NAME_CONVERSION[property_name]
  end

  def prettify_user_role(user_role)
    User::USER_ROLE_CONVERSION[user_role]
  end

  def ticket_property_name_conversion
    Ticket::TICKET_PROPERTY_NAME_CONVERSION
  end

  ## purpose
  #  -transforms ticket status into css class name. css class name is
  #   used to change color of ticket status text
  def css_classify(ticket_status)
    case ticket_status
    when 'Open'               then 'openticket'
    when 'In Progress'        then 'inprogress'
    when 'Resolved'           then 'resolvedticket'
    when 'Add. Info Required' then 'addinfo'
    end
  end

  ## params
  #  -arr:   arr of string objects
  ## purpose
  #  -transforms the array into string in the format of JavaScript array
  #   in order to pass in erb values into JS script
  ## return value
  #  -string
  def array_for_js(arr)
    "['#{arr.join('\',\'')}']"
  end

  ## return value
  #  -array of Date objects for the last 14 days
  def last_14_days
    result = [Date.today - 13]
    13.times { |_| result << result[-1] + 1 }
    result
  end

  ## return value
  #  -array of string objects of formated month and day
  #   (ex. ['Feb 21', 'Feb 22', 'Feb 23'...])
  def x_axis_dates
    last_14_days.map do |date|
      iso_hash = Date._iso8601(date.iso8601)
      "#{Date::ABBR_MONTHNAMES[iso_hash[:mon]]} %02d" % [iso_hash[:mday]]
    end
  end

  ## return value
  #  -array of string objects of date in ISO 8601 format
  #   (ex. ['2021-02-13', '2021-02-14', '2021-02-15'...])
  def last_14_iso_dates
    last_14_days.map{ |date| date.iso8601 }
  end

  ## purpose
  #  -returns a JavaScript friendly array that contains all unresolved
  #   ticket counts for the last 14 days
  ## return value
  #  -string representation of JS array
  def all_open_ticket_count
    result = last_14_iso_dates.map do |iso_date|
      open_count = Ticket.open_count(@db, iso_date).first
      open_count ? open_count['count'].to_i : 0
    end
    array_for_js(result)
  end

  ## params
  #  -project_id:   string or int
  ## purpose
  #  -returns an array of int, each element being unresolved ticket
  #   count for given project id
  ## return value
  #  -array of int
  def project_open_ticket_count(project_id)
    result = last_14_iso_dates.map do |iso_date|
      result = Ticket.open_count_for(@db, iso_date, project_id).first
      result ? result['count'].to_i : 0
    end
    result
  end

  ## params
  #  -project_ids:   array of string or int
  ## purpose
  #  -returns a string containing an array of all open ticket counts for
  #   all the project ids in the argument
  ## return value
  #  -string representation of JS array
  def all_project_open_ticket_count(project_ids)
    # count_arr is an array of open ticket count arrays
    # ex. [ [1, 4, 2, 5, 6, 11, 13, 14, 55, 21, 38, 99, 121, 31],
    #       [67, 3, 1, 9, 7, 2, 16, 28, 66, 13, 41, 32, 68, 89], ... ]
    count_arr = project_ids.map { |id| project_open_ticket_count(id) }

    # result is an array of 14 int elements, each the total sum of open
    # ticket counts for each day (represented as 'ind') for all projects
    # in the project_ids
    result = (0..13).map do |ind|
      (0...count_arr.size).reduce(0) { |sum, n| sum + count_arr[n][ind].to_i }
    end
    array_for_js(result)
  end

  ## serves similar function as "all_open_ticket_count" method but
  ## for resolved ticket counts
  def all_resolved_ticket_count
    result = last_14_iso_dates.map do |iso_date|
      resolved_count = Ticket.resolved_count(@db, iso_date).first
      resolved_count ? resolved_count['count'].to_i : 0
    end
    array_for_js(result)
  end

  ## serves similar function as "project_open_ticket_count" method but
  ## for resolved ticket counts
  def project_resolved_ticket_count(project_id)
    result = last_14_iso_dates.map do |iso_date|
      result = Ticket.resolved_count_for(@db, iso_date, project_id).first
      result ? result['count'].to_i : 0
    end
    result
  end

  ## serves similar function as "all_project_open_ticket_count" method but
  ## for resolved ticket counts
  def all_project_resolved_ticket_count(project_ids)
    count_arr = project_ids.map { |id| project_resolved_ticket_count(id) }

    result = (0..13).map do |ind|
      (0...count_arr.size).reduce(0) { |sum, n| sum + count_arr[n][ind].to_i }
    end
    array_for_js(result)
  end

  ## params
  #  -project_ids:   arr of string or int
  ## purpose
  #  -returns an array of Ticket class instance objects for tickets
  #   submitted within the last 3 days
  ## return value
  #  -an array of Ticket class instance objects
  def last_3days_tickets_for(project_ids)
    result = []
    project_ids.each do |project_id|
      tickets = Ticket.last_3days_for(@db, project_id)
      result += tickets.map { |ticket| ticket }
    end
    result
  end

  ## params
  #  -project_ids:   arr of string or int
  ## purpose
  #  -returns an array of Ticket class instance objects for all tickets
  #   submitted for the project ids in the argument
  ## return value
  #  -an array of Ticket class instance objects
  def all_tickets_for(project_ids)
    result =[]
    project_ids.each do |project_id|
      tickets = Ticket.all_for(@db, project_id)
      result += tickets.map { |ticket| ticket }
    end
    result
  end

  ## params
  #  -project_id:   string or int
  ## purpose
  #  -adds a new key:value to Ticket class instance object.
  #   new key is 'sub_name' and value is the submitter's name taken from
  #   'users' table
  #   ex) {'sub_name' => 'Thomas Jefferson' }
  ## return value
  #  -an array of Ticket class instance objects
  def all_project_tickets_with_names(project_id)
    Ticket.all_for(@db, project_id).map do |ticket|
      ticket['sub_name'] = User.name(@db, ticket['submitter_id'])
      ticket
    end
  end

#------For following 4 methods-------#
  ## params
  #  -tickets:   array of Ticket class instance objects
  ## purpose
  #  -selects tickets based on condition
  ## return value
  #  -an array of Ticket class instance objects
#-------------------------------------#

  def unresolved_tickets(tickets)
    tickets.select { |t| t['status'] != 'Resolved' }
  end

  def resolved_tickets(tickets)
    tickets.select { |t| t['status'] == 'Resolved' }
  end

  def dev_assigned_tickets(tickets)
    tickets.select { |t| t['dev_name'] == session[:user].name }
  end

  def unassigned_tickets(tickets)
    tickets.select { |t| t['dev_name'] == 'Unassigned' }
  end

  ## params
  #  -edit_info: EditInfo struct that has new ticket properties as its attr
  #  -tickets:   array of Ticket class instance objects
  ## purpose
  #  -Detects which ticket info are updated and returns a new hash
  #   of only the changing info's field name and value as key/value pair
  ## return value
  #  -Hash of only the editing ticket info fields and new values OR
  #   returns nil if there were no changing fields
  def create_updates_hash(edit_info, ticket)
    # edit_info attr: :title, :description, :priority,
    #                 :status, :type, :developer_id
    if update_exists?(edit_info, ticket)
      edit_info.reject { |k, v| ticket.send(k) == v }
    else
      nil
    end
  end

  ## params
  #  -edit_info: Hash of key:value pairs for each ticket edit category
  #  -tickets:   array of Ticket class instance objects
  ## purpose
  #  -returns True if any of the values in "edit_info" Struct differs
  #   from the values in "ticket" Ticket class instance.
  ## return value
  #  -true of false
  def update_exists?(edit_info, ticket)
    edit_info.keys.any? do |key|
      edit_info[key] != ticket.send(key)
    end
  end

  ## params
  #  -updates_hash:  Hash of only the updating ticket info fields and new values
  #  -ticket:        updating Ticket class instance object
  ## purpose
  #  -returns a hash with changing ticket property names as keys,
  #   and pre-update values as values.
  ## return value
  #  -Hash of string key and string values
  def pre_update_values(updates_hash, ticket)
    updates_hash.each_with_object({}) do |(k, _), result|
      result[k] = ticket.send(k)
    end
  end

  ## params
  #  -pre_updates:  Hash of updating ticket's pre-update values
  #  -updates:      Hash of only the updating ticket info fields and new values
  #  -user_id:      string or int
  #  -ticket_id:    string or int
  ## purpose
  #  -returns an array of arrays. Each element is an array of each
  #   updating field name, previous & current value, updater name,
  #   and 'updated on' timestamp
  ## return value
  #  -array of string. plugs directly into Ticket.create_history
  def update_histories(pre_updates, updates, user_id, ticket_id)
    pre_updates.map do |k, v|
      if k == :developer_id
        new_dev_name = User.name(@db, updates[k])
        k = :developer_name
        updates[k] = new_dev_name
        v = User.name(@db, v)
      end
      [k.to_s, v, updates[k], user_id, ticket_id]
    end
  end

  ## params
  #  -object_key:    string
  #  -file_content:  binary file content
  ## purpose
  #  -Uploads the file content to S3 with the specified object_key.
  ## return value
  #  -true or false
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

  ## params
  #  -object_key:    string
  ## purpose
  #  -Downloads the object specified by object key from S3, and returns it.
  #   If no such object exists or an error happens, returns nil.
  ## return value
  #  -s3 file object or nil
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

# -------------START OF ROUTES------------------------------------------------ #
# -------------START OF ROUTES------------------------------------------------ #
# -------------START OF ROUTES------------------------------------------------ #
# -------------START OF ROUTES------------------------------------------------ #
# -------------START OF ROUTES------------------------------------------------ #
# -------------START OF ROUTES------------------------------------------------ #

before do
  if ENV['RACK_ENV'] == 'test'
    @db = PG.connect(dbname: 'bugtrack_test')
  elsif ENV['RACK_ENV'] == 'development'
    @db = PG.connect(dbname: 'bugtracker')
  else
    @db = PG.connect(database_url(ENV['DATABASE_URL']))
  end
end

after do
  @db.close
end

get '/' do
  redirect '/home'
end

get '/home' do
  File.read(File.join('public', 'index.html'))
end

def tickets_without_dev(tickets)
  tickets.select { |ticket| ticket['dev_name'] == 'Unassigned' }
end

get '/dashboard' do
  require_signed_in_user

  @x_axis_dates = array_for_js(x_axis_dates)

  if session[:user].role == 'admin'
    @tickets_without_devs = tickets_without_dev( Ticket.all(@db) )
    @open_ticket_count = all_open_ticket_count
    @resolved_ticket_count = all_resolved_ticket_count
    @last_3days_tickets = Ticket.last_3days(@db)
  elsif session[:user].role == 'project_manager'
    assigned_projects = session[:user].assigned_projects(@db)

    @tickets_without_devs = tickets_without_dev( Ticket.all(@db) )
    @open_ticket_count = all_project_open_ticket_count(assigned_projects)
    @resolved_ticket_count = all_project_resolved_ticket_count(assigned_projects)
    @last_3days_tickets  = last_3days_tickets_for(assigned_projects)
  else
    assigned_projects = session[:user].assigned_projects(@db)

    @open_ticket_count = all_project_open_ticket_count(assigned_projects)
    @resolved_ticket_count = all_project_resolved_ticket_count(assigned_projects)
    @last_3days_tickets  = last_3days_tickets_for(assigned_projects)
  end

  erb :dashboard, layout: false
end

# -------------USERS---------------------------------------------------------- #
# -------------USERS---------------------------------------------------------- #
# -------------USERS---------------------------------------------------------- #
# -------------USERS---------------------------------------------------------- #
# -------------USERS---------------------------------------------------------- #
# -------------USERS---------------------------------------------------------- #

# VIEW USER REGISTRATION FORM
get '/register' do
  session.clear
  erb :register, layout: false
end

# POST NEW USER REGISTRATION
post '/register' do
  full_name = "#{params[:first_name]} #{params[:last_name]}"
  email = params[:email]
  username = params[:username]
  password = params[:password]

  error = []
  unless User.unique_login?(@db, username)
    error << 'That username is already taken'
  end
  unless User.unique_email?(@db, email)
    error << 'That email is already in use'
  end

  if error.size > 0
    session[:error] = error
    erb :register, layout: false
  else
    new_user = User.register(@db, full_name, username, encrypt(password), email)

    session.clear
    session[:user] = new_user

    session[:success] = 
      "You are now logged in to your new account, #{session[:user].name}."
    redirect '/dashboard'
  end
end

# VIEW LOG IN FORM
get '/login' do
  session.clear
  erb :login, layout: false
end

# POST USER LOG IN
post '/login' do
  username = params[:username]
  password = params[:password]

  login = User.user_with_login(@db, username)

  if login && correct_password?(password, login['password'])
    error = nil
  else
    error = 'Username or password was incorrect.'
  end

  if error
    session[:error] = error
    erb :login, layout: false
  else
    session.clear
    session[:user] = User.new(@db, login['id'])

    redirect '/dashboard'
  end
end

get '/login/demo/:role' do
  demo_role = params[:role]
  login_for_role(demo_role)

  session[:success] =
      "Welcome, #{session[:user].name}."
  redirect '/dashboard'
end

post '/login/demo/:role' do
  demo_role = params[:role]
  login_for_role(demo_role)

  session[:success] =
      "Welcome, #{session[:user].name}."
  redirect '/dashboard'
end

# LOG OUT USER
get '/logout' do
  session.clear
  redirect '/home'
end

# USER PROFILE
get '/profile' do
  require_signed_in_user
  full_name = session[:user].name

  @first_name = full_name.split(' ')[0..-2].join(' ')
  @last_name = full_name.split(' ')[-1]
  erb :profile, layout: false
end

# UPDATE USER INFO (NAME, EMAIL)
post '/profile/info_update' do
  require_signed_in_user

  full_name = "#{params[:first_name]} #{params[:last_name]}"
  email = params[:email]

  all_emails = User.all_emails(@db)
  all_emails.delete(session[:user].email)
  error = 'That email is already in use' if all_emails.index(email)

  if error
    session[:error] = error
    redirect '/profile'
  else
    session[:user].update_info(@db, full_name, email)
    session[:success] = 'You successfully updated your information.'
    redirect '/profile'
  end
end

# UPDATE USER PASSWORD
post '/profile/password_update' do
  require_signed_in_user

  old_pass = params[:pass_current]
  hashed_pass = session[:user].password(@db)
  new_pass = encrypt(params[:pass_new])

  if correct_password?(old_pass, hashed_pass)
    session[:user].update_password(@db, new_pass)
    session[:success] = 'You successfully updated your password.'
    redirect '/profile'
  else
    session[:error] = 'Current password was incorrect.'
    redirect '/profile'
  end
end

# VIEW USER ROLES
get '/users' do
  required_signed_in_admin

  @users = User.all_users(@db)
  @roles = User::USER_ROLE_CONVERSION.keys.reject { |k,v| k == 'Unassigned' }

  erb :assign_roles, layout: false
end

# UPDATE USER ROLES
post '/users' do
  required_signed_in_admin

  id = params[:user_id]
  role = params[:role]
  name = User.name(@db, id)

  User.assign_role(@db, role, id)

  pretty_role = prettify_user_role(role)
  session[:success] =
    "You successfully assigned the role of '#{pretty_role}' to #{name}"
  redirect '/users'
end

# -------------PROJECTS------------------------------------------------------- #
# -------------PROJECTS------------------------------------------------------- #
# -------------PROJECTS------------------------------------------------------- #
# -------------PROJECTS------------------------------------------------------- #
# -------------PROJECTS------------------------------------------------------- #
# -------------PROJECTS------------------------------------------------------- #

# VIEW ALL USER'S ASSIGNED PROJECTS
get '/projects' do
  require_signed_in_user

  if session[:user].role == 'admin'
    @projects = Project.all(@db)
  else
    assigned_projects = session[:user].assigned_projects(@db)
    @projects = all_details_for(assigned_projects)
  end

  erb :projects, layout: false
end

# POST A NEW PROJECT
post '/projects/new' do
  required_signed_in_admin

  @project_name = params[:name].strip
  @description = params[:description].strip

  error = error_for(@project_name)
  if error
    session[:error] = error
    redirect '/projects'
  else
    Project.create(@db, @project_name, @description)
    session[:success] = 'You have successfully created a new project.'
    redirect '/projects'
  end
end

# VIEW ASSIGN USER TO PROJECT FORM
get '/projects/:id/users' do
  required_signed_in_pm

  @project_id = params[:id]
  @project_manager = 'Not Assigned'
  @project = Project.new(@db, @project_id)
  @tickets = all_project_tickets_with_names(@project.id)

  assigned_users = @project.assigned_users(@db)

  assigned_users.each do |user|
    @project_manager = user['name'] if user['role'] == 'project_manager'
  end
  
  assigned_user_ids = assigned_users.map { |user| user['id'] }
  users = User.all_users(@db).map do |user|
    if assigned_user_ids.include?(user['id'])
      user['assigned?'] = true
    end
    user
  end

  @pms = users.select { |user| user['role'] == 'project_manager' }
  @devs = users.select { |user| user['role'] == 'developer' }
  @qas = users.select { |user| user['role'] == 'quality_assurance' }

  erb :assign_users, layout: false
end

# POST USER ASSIGNMENTS
post '/projects/:id/users' do
  required_signed_in_pm

  project = Project.new(@db, params[:id])

  if params[:assigned_users].nil?
    project.unassign_all(@db)

    session[:error] = 'There are no users assigned to this project.'
    redirect "/projects/#{project.id}/users"
  else
    user_assignments = params[:assigned_users].map! do |user|
      id, role = user.split(ID_ROLE_DELIMITER)
      {'id' => id, 'role' => role}
    end

    assigned_users = project.assigned_users(@db)
    assigned_user_ids = assigned_users.map { |user| user['id'] }

    new_assigned_users = user_assignments.reject do |user|
      assigned_user_ids.include?(user['id'])
    end
    # Assign new users to project
    new_assigned_users.each do |new_user|
      project.assign_user( @db, new_user['id'], new_user['role'] )
    end

    new_assigned_users_ids = user_assignments.map { |user| user['id'] }
    unassigned_users = assigned_user_ids.reject do |user_id|
      new_assigned_users_ids.include?(user_id)
    end
    # Unassign users from project
    unassigned_users.each do |user_id|
      project.unassign_user( @db, user_id )
    end

    session[:success] = 'You have successfully made new user assignments.'
    redirect "/projects/#{project.id}/users"
  end
end

# VIEW PROJECT DETAILS
# includes: name, description, assigned users, and tickets for that project
get '/projects/:id' do
  require_signed_in_user

  @x_axis_dates = array_for_js(x_axis_dates)
  @project = Project.new(@db, params[:id])
  @assigned_users = @project.assigned_users(@db)
  @tickets = all_project_tickets_with_names(@project.id)

  @types = Ticket::TICKET_TYPE
  @priorities = Ticket::TICKET_PRIORITY

  @open_ticket_count = array_for_js(project_open_ticket_count(@project.id))
  @resolved_ticket_count = array_for_js(project_resolved_ticket_count(@project.id))

  erb :project, layout: false
end

# POST PROJECT EDITS
# edits name and/or description
post '/projects/:id' do
  required_signed_in_pm

  @name = params[:name].strip
  @description = params[:description].strip
  project = Project.new(@db, params[:id])

  current_name = Project.name(@db, project.id)

  if @name != current_name
    error = error_for(@name)
  end

  if error
    session[:error] = error
    redirect "/projects/#{project.id}"
  else
    project.update(@db, @name, @description)

    session[:success] = 'You have successfully updated the project.'
    redirect "/projects/#{project.id}"
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
get '/tickets' do
  require_signed_in_user

  @types = Ticket::TICKET_TYPE
  @priorities = Ticket::TICKET_PRIORITY
  all_tickets = Ticket.all(@db)
  @submitted_tickets = 
    all_tickets.select { |t| t['submitter_id'] == session[:user].id }

  if session[:user].role == 'admin'
    all_projects = Project.all(@db).map { |project| project['id'] }

    @projects = projects(all_projects)
    @unresolved_tickets = unresolved_tickets(all_tickets)
    @resolved_tickets = resolved_tickets(all_tickets)
  else
    assigned_projects = session[:user].assigned_projects(@db)
    all_projects_tickets = all_tickets_for(assigned_projects)

    @projects = projects(assigned_projects)
    @unresolved_tickets = unresolved_tickets(all_projects_tickets)
    @resolved_tickets = resolved_tickets(all_projects_tickets)
    if session[:user].role == 'developer'
      @dev_assigned_tickets = dev_assigned_tickets(all_projects_tickets)
    end
  end

  if params[:dev] == 'unassigned'
    if session[:user].role == 'admin'
      @unresolved_tickets = unassigned_tickets(all_tickets)
    elsif session[:user].role == 'project_manager'
      @unresolved_tickets = unassigned_tickets(all_projects_tickets)
    end
    @resolved_tickets = []
    @submitted_tickets = []
  end

  erb :tickets, layout: false
end

# POST A NEW TICKET
post '/tickets/new' do
  require_signed_in_user

  title = params[:title].strip
  description = params[:description].strip
  type = params[:type]
  priority = params[:priority]
  project_id = params[:project_id]

  # default developer_id to 0, or "Unassigned".
  # admin or project manager must assign dev.
  new_ticket_info = ['Open', title, description, type, priority,
                     session[:user].id, project_id, 0]
  Ticket.create(@db, new_ticket_info)

  session[:success] = 'You have successfully submitted a new ticket.'
  redirect '/tickets'
end

# POST A NEW TICKET FROM A PROJECT DETAILS VIEW
post '/tickets/new/from-project' do
  require_signed_in_user

  title = params[:title].strip
  description = params[:description].strip
  type = params[:type]
  priority = params[:priority]
  project_id = params[:project_id]

  # default developer_id to 0, or "Unassigned".
  # admin or project manager must assign dev.
  new_ticket_info = ['Open', title, description, type, priority,
                     session[:user].id, project_id, 0]
  Ticket.create(@db, new_ticket_info)

  session[:success] = 'You have successfully submitted a new ticket.'
  redirect "/projects/#{project_id}"
end

# VIEW TICKET DETAILS
# includes: ticket properties, comments, attachments, & update history.
get '/tickets/:id' do
  require_signed_in_user

  @ticket = Ticket.new(@db, params[:id])

  @priorities = Ticket::TICKET_PRIORITY
  @statuses = Ticket::TICKET_STATUS
  @types = Ticket::TICKET_TYPE

  project = Project.new(@db, @ticket.project_id)
  @developers = 
    project.assigned_users(@db).select { |user| user['role'] == 'developer' }

  @attachments = @ticket.attachments(@db)
  @histories = @ticket.histories(@db)
  @comments = @ticket.comments(@db)

  erb :ticket, layout: false
end

# POST TICKET EDITS
post '/tickets/:id' do
  require_signed_in_user

  ticket = Ticket.new(@db, params[:id])

  new_title = params[:title].strip
  new_desc = params[:description].strip
  new_priority = params[:priority]
  new_status = params[:status]
  new_type = params[:type]
  new_dev_id = params[:developer_id]

  edit_info = {
                :title        => new_title,
                :description  => new_desc,
                :priority     => new_priority,
                :status       => new_status,
                :type         => new_type,
                :developer_id => new_dev_id
              }

  updates = create_updates_hash(edit_info, ticket)
  if updates
    pre_updates = pre_update_values(updates, ticket)
    ticket.update(@db, updates)

    update_history_arr =
      update_histories(pre_updates, updates, session[:user].id, ticket.id)
    Ticket.create_history(@db, update_history_arr)

    session[:success] = 'You have successfully made change(s) to a ticket.'
    redirect "/tickets/#{ticket.id}"
  else
    redirect "/tickets/#{ticket.id}"
  end
end

# POST TICKET COMMENT
post '/tickets/:id/comment' do
  require_signed_in_user

  comment = params[:comment].strip
  ticket_id = params[:id]
  Ticket.create_comment(@db, comment, session[:user].id, ticket_id)

  session[:success] = 'You succesfully posted a comment'
  redirect "/tickets/#{ticket_id}"
end

# UPLOAD A FILE AS ATTACHMENT TO A TICKET
post '/upload/:id' do
  require_signed_in_user

  if ( params[:file] &&
      ( tmpfile = params[:file][:tempfile] ) &&
      ( object_key = params[:file][:filename] ) )
    if s3_object_uploaded?(object_key, File.read(tmpfile))
      Ticket.create_attachment(@db,
                               object_key,
                               session[:user].id,
                               params[:notes],
                               params[:id])
      session[:success] = "'#{object_key}' was attached successfully."
    end
  end
  redirect "/tickets/#{params[:id]}"
end

# DOWNLOAD AND RETURN ATTACHMENT FILE TO BE VIEWED ON BROWSER
get '/tickets/:id/:filename' do
  require_signed_in_user

  object_key = params[:filename]

  response = s3_object_download(object_key)

  if response
    headers['Content-Type'] = response[:content_type]
    headers['Content-Disposition'] = response[:content_disposition]
    response.body
  end
end

# CATCH ALL ERROR ROUTE TO DISPLAY 404 PAGE
error 400..510 do
  File.read(File.join('public', '404.html'))
end