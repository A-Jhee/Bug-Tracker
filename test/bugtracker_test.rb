# require 'simplecov'
# SimpleCov.start

ENV['RACK_ENV'] = 'test'

require 'minitest/autorun'
require 'minitest/reporters'
require 'rack/test'
require 'pg'

MiniTest::Reporters.use!

require_relative '../bugtracker'
require_relative '../models/user'
require_relative '../models/project'
require_relative '../models/ticket'

class BugtrackerTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def setup
    @test_db = PG.connect(dbname: 'bugtrack_test')
    sql = <<~SQL
    TRUNCATE projects,
             projects_users_assignments,
             tickets,
             ticket_comments,
             ticket_update_history,
             ticket_attachments
             RESTART IDENTITY;
    SQL
    @test_db.exec(sql)
    
    create_dummy_projects
    create_dummy_tickets
    assign_users_to_projects
  end

  def teardown
    @test_db.close
  end

  # ----- HELPER METHODS ----- #
  # ----- HELPER METHODS ----- #
  # ----- HELPER METHODS ----- #

  def session
    last_request.env['rack.session']
  end

  def admin_session
    { "rack.session" => { user: User.new(@test_db, '1') } }
  end

  def pm_session
    { "rack.session" => { user: User.new(@test_db, '2') } }
  end
  
  def dev_session
    { "rack.session" => { user: User.new(@test_db, '3') } }
  end

  def qa_session
    { "rack.session" => { user: User.new(@test_db, '4') } }
  end

  def assert_role(role)
    assert_equal 200, last_response.status
    assert_includes last_response.body, role
  end

  def logout
    session.clear
  end

  def create_dummy_projects
    # project 1
    Project.create(@test_db, 'bugtracker', 'WebApp built on PSQL to track bug')
    # project 2
    Project.create(@test_db, 'finance manager', 'Personal finance/budget manager')
    # project 3
    Project.create(@test_db, 'text editor', 'simple text editor')
  end

  def create_dummy_tickets
    # ticket 1
    Ticket.create(@test_db, ['Open', 'Unable to login',
                             'Create a login functionality',
                             'Bug/Error Report', 'Low', 4, 3, 1])
    # ticket 2
    Ticket.create(@test_db, ['In Progress', 'Object models',
                             'models for all database handling',
                             'Feature Request', 'High', 2, 1, 3])
    # ticket 3
    Ticket.create(@test_db, ['Resolved', 'Test suite',
                             'Create test suites for all',
                             'Service Request', 'Critical', 1, 2, 2])
    # ticket 4
    Ticket.create(@test_db, ['Add. Info Required', 'frontend/css',
                             'integrate bootstrap/css',
                             'Other', 'High', 3, 1, 4])
  end

  def assign_users_to_projects
    # project 1: pm, dev, qa
    project1 = Project.new(@test_db, '1')
    project1.assign_user(@test_db, '2', 'project_manager')
    project1.assign_user(@test_db, '3', 'developer')
    project1.assign_user(@test_db, '4', 'quality_assurance')
    # project 2: admin, dev
    project2 = Project.new(@test_db, '2')
    project2.assign_user(@test_db, '1', 'admin')
    project2.assign_user(@test_db, '3', 'developer')
    # project 3: pm, qa
    project3 = Project.new(@test_db, '3')
    project3.assign_user(@test_db, '2', 'project_manager')
    project3.assign_user(@test_db, '4', 'quality_assurance')
  end

  def create_dummy_comment(commenter_id, ticket_id)
    sql = <<~SQL
      INSERT INTO ticket_comments (comment, commenter_id, ticket_id)
           VALUES ('This message is for testing purposes only.', $1, $2)
    SQL
    @test_db.exec_params(sql, [ commenter_id, ticket_id ])
  end

  def delete_test_user
    sql = <<~SQL 
      DELETE FROM users
            WHERE name = 'George Washington'
              AND email = 'gwash@potus.gov';
    SQL
    @test_db.exec(sql)
  end

  # ----- END OF HELPER METHODS ----- #
  # ----- END OF HELPER METHODS ----- #

# -------------REGISTER/LOGIN/USERS/DASHBOARD--------------------------------- #
# -------------REGISTER/LOGIN/USERS/DASHBOARD--------------------------------- #
# -------------REGISTER/LOGIN/USERS/DASHBOARD--------------------------------- #
# -------------REGISTER/LOGIN/USERS/DASHBOARD--------------------------------- #
# -------------REGISTER/LOGIN/USERS/DASHBOARD--------------------------------- #
# -------------REGISTER/LOGIN/USERS/DASHBOARD--------------------------------- #

  # VIEW REGISTER FORM
  def test_get_register
    get '/register'

    assert_nil session[:user]
    assert_includes last_response.body, "Already have an account?"
    assert_includes last_response.body, "Log in instead"
    assert_includes last_response.body, %q(id="username_register")
    assert_includes last_response.body, %q(id="email_register")
    assert_includes last_response.body, %q(id="password")
    assert_includes last_response.body, %q(data-parsley-equalto="#password")
  end

  # REGISTER NEW ACCOUNT
  def test_post_register
    # invalid: username already taken -> error
    post '/register', {first_name: 'George', last_name: 'Washington',
                       email: 'gwash@potus.gov', username: 'dev',
                       password: 'imTHEfirst1'}

    assert_includes last_response.body, 'That username is already taken'
    assert_includes last_response.body, 'Already have an account?'
    assert_includes last_response.body, 'dev'

    # invalid: email already in use -> error
    post '/register', {first_name: 'George', last_name: 'Washington',
                       email: 'admin@demo.com', username: 'gwash',
                       password: 'imTHEfirst1'}

    assert_includes last_response.body, 'Already have an account?'
    assert_includes last_response.body, 'admin@demo.com'

    get '/login'
    # passes all validation
    post '/register', {first_name: 'George', last_name: 'Washington',
                       email: 'gwash@potus.gov', username: 'gwash',
                       password: 'imTHEfirst1'}

    # assert_equal 200, last_response.status
    
    assert_equal 302, last_response.status

    get last_response["Location"]
    assert_equal 200, last_response.status

    assert_includes last_response.body, 'Dashboard'

    delete_test_user
  end
  
  # VIEW LOGIN FORM
  def test_get_login
    get '/login'

    assert_nil session[:user]
    assert_includes last_response.body, %q(<title>GECKO bug tracker</title>)
    assert_includes last_response.body, "Don't have an account?"
    assert_includes last_response.body, "Register"
    assert_includes last_response.body, %q(type="submit">Login)
    assert_includes last_response.body, "Or Login With A Demo Account"
    assert_includes last_response.body, %q(type="submit">Admin)
    assert_includes last_response.body, %q(type="submit">Project Manager)
    assert_includes last_response.body, %q(type="submit">Developer)
    assert_includes last_response.body, %q(type="submit">QA)
  end

  # POST LOGIN INFO
  def test_post_login
    # invalid login
    post '/login', {username: 'wrong_login', password: 'admin1admin1'}

    assert_equal 200, last_response.status
    assert_includes last_response.body, 'Username or password was incorrect.'

    # invalid password
    post '/login', {username: 'admin', password: 'wrong_pass'}

    assert_equal 200, last_response.status
    assert_includes last_response.body, 'Username or password was incorrect.'

    # valid login
    post '/login', {username: 'admin', password: 'admin1admin1'}
    assert_equal 302, last_response.status
    assert session[:user]
    assert_equal 'admin', session[:user].login
    assert_equal 'admin@demo.com', session[:user].email

    get last_response["Location"]
    assert_equal 200, last_response.status
  end

  # TRIGGER LOGOUT THEN REDIRECT TO /LOGIN
  def test_get_logout
    get '/logout', {}, qa_session

    assert_equal 302, last_response.status
    assert session.empty?
  end


  # VIEW DASHBOARD ADMIN
  def test_dashboard_demo
    post '/login/demo/admin', {}

    assert_equal 302, last_response.status
    get last_response["Location"]

    assert_role('Admin')
    assert_includes last_response.body, 'Ticket Assignment'
    assert_includes last_response.body, 'Dashboard'

    post '/login/demo/project_manager', {}

    assert_equal 302, last_response.status
    get last_response["Location"]

    assert_role('Project Manager')
    assert_includes last_response.body, 'Ticket Assignment'
    assert_includes last_response.body, 'Tickets Overview'
    assert_includes last_response.body, 'Tickets Opened in the Past 3 Days'

    post '/login/demo/developer', {}

    assert_equal 302, last_response.status
    get last_response["Location"]

    assert_role('Developer')

    post '/login/demo/quality_assurance', {}

    assert_equal 302, last_response.status
    get last_response["Location"]

    assert_role('Quality Assurance')
  end

  # VIEW PROFILE EDIT FORM
  def test_get_profile
    get '/profile', {}, admin_session

    assert_role('Admin')
    assert_includes last_response.body, 'admin@demo.com'
    assert_includes last_response.body, 'Change Personal Information'
    assert_includes last_response.body, 'Update Password'

    get '/profile', {}, pm_session
    
    assert_role('Project Manager')
    assert_includes last_response.body, 'project_manager@demo.com'

    get '/profile', {}, dev_session

    assert_role('Developer')
    assert_includes last_response.body, 'developer@demo.com'

    get '/profile', {}, qa_session

    assert_role('Quality Assurance')
    assert_includes last_response.body, 'quality_assurance@demo.com'
  end

  # POST PROFILE INFO UPDATE (NAME, EMAIL)
  def test_post_profile_info_update
    post '/profile/info_update',
         {first_name: 'Freddy', last_name: 'Mercury', email: 'fmer@queen.com'},
         dev_session

    assert_equal 302, last_response.status
    assert_equal 'You successfully updated your information.', session[:success]
    get last_response["Location"]

    assert_includes last_response.body, 'Freddy'
    assert_includes last_response.body, 'Mercury'
    assert_includes last_response.body, 'fmer@queen.com'

    post '/profile/info_update',
         {first_name: 'Freddy', last_name: 'Mercury',
          email: 'project_manager@demo.com'},
         dev_session

    assert_equal 302, last_response.status
    assert_equal 'That email is already in use', session[:error]

    post '/profile/info_update',
         {first_name: 'Developer', last_name: 'Demo',
            email: 'developer@demo.com'},
         dev_session
  end

  # POST PASSWORD UPDATE
  def test_post_profile_pass_update
    post '/profile/password_update',
         {pass_current: 'admin1admin1', pass_new: 'brandNEWpass'},
         admin_session

    assert_equal 302, last_response.status
    assert_equal 'You successfully updated your password.', session[:success]

    post '/profile/password_update',
         {pass_current: 'wrong_pass', pass_new: 'justANYpass'},
         admin_session

    assert_equal 302, last_response.status
    assert_equal 'Current password was incorrect.', session[:error]

    post '/profile/password_update',
         {pass_current: 'brandNEWpass', pass_new: 'admin1admin1'},
         admin_session
  end
  
  # VIEW ROLE ASSIGNMENT FORM
  def test_get_user_roles
    get '/users', {}, pm_session

    assert_equal 302, last_response.status
    assert_equal 'You are not authorized for that action', session[:error]

    get last_response["Location"]
    assert_includes last_response.body, 'Dashboard'

    get '/users', {}, admin_session

    assert_equal 200, last_response.status
    assert_includes last_response.body, 'Manage Users'
    assert_includes last_response.body, 'Assign User Roles'
    assert_includes last_response.body, %q(Assign Role</button>)
  end

  # UPDATE ROLE ASSIGNMENT
  def test_post_user_roles
    post '/users', {user_id: '4', role: 'project_manager'}, admin_session

    assert_equal 302, last_response.status
    assert_equal "You successfully assigned the role of 'Project Manager' to " +
    "Quality Assurance Demo", session[:success]

    post '/users', {user_id: '4', role: 'quality_assurance'}, admin_session
  end

# -------------PROJECTS------------------------------------------------------- #
# -------------PROJECTS------------------------------------------------------- #
# -------------PROJECTS------------------------------------------------------- #
# -------------PROJECTS------------------------------------------------------- #
# -------------PROJECTS------------------------------------------------------- #
# -------------PROJECTS------------------------------------------------------- #

  def test_get_projects
    get '/projects', {}, admin_session

    assert_role('Admin')
    assert_includes last_response.body, 'bugtracker'
    assert_includes last_response.body, 'finance manager'
    assert_includes last_response.body, 'Personal finance/budget manager'
    assert_includes last_response.body, 'text editor'
    assert_includes last_response.body, 'Create New Project'

    get '/projects', {}, pm_session
  
    assert_role('Project Manager')
    assert_includes last_response.body, 'Projects Overview'
    assert_includes last_response.body, 'bugtracker'
    assert_includes last_response.body, 'text editor'

    refute_includes last_response.body, 'Create New Project'
    refute_includes last_response.body, 'finance manager'

    get '/projects', {}, dev_session

    assert_role('Developer')
    assert_includes last_response.body, 'Projects Overview'
    assert_includes last_response.body, 'bugtracker'
    assert_includes last_response.body, 'finance manager'

    refute_includes last_response.body, 'Create New Project'
    refute_includes last_response.body, 'text editor'

    get '/projects', {}, qa_session

    assert_role('Quality Assurance')
    assert_includes last_response.body, 'Projects Overview'
    assert_includes last_response.body, 'bugtracker'
    assert_includes last_response.body, 'text editor'

    refute_includes last_response.body, 'Create New Project'
    refute_includes last_response.body, 'finance manager'
  end

  # post a new project with not-unique name or wrong auth: invalid
  def test_post_projects_new_invalid
    error ='That project name is already in use. A project name must be unique.'

    post '/projects/new',
         {name: 'bugtracker', description: 'new desc 42'},
         admin_session

    assert_equal 302, last_response.status
    assert_equal error, session[:error]

    post '/projects/new',
         {name: 'valid name', description: 'valid desc 23'},
         pm_session

    assert_equal 302, last_response.status
    assert_equal 'You are not authorized for that action', session[:error]
  end

  # post a new project: valid
  def test_post_projects_new_valid
    success = 'You have successfully created a new project.'

    post '/projects/new',
         {name: 'test project', description: 'valid description'},
         admin_session

    assert_equal 302, last_response.status
    assert_equal success, session[:success]

    get last_response['Location']
    assert_includes last_response.body, 'test project'
    assert_includes last_response.body, 'valid description'
  end

  # render assign users form
  def test_get_projects_id_users
    get "/projects/1/users", {}, pm_session

    assert_role('Project Manager')
    assert_includes last_response.body, 'Project Assignment'
    assert_includes last_response.body, 'bugtracker'
    assert_includes last_response.body, 'Assign Users to Project'
    assert_includes last_response.body, %q(type="submit">Change User Assignments)
  end

  # post new user assignments to a project
  def test_post_projects_id_users
    error = 'There are no users assigned to this project.'
    success = 'You have successfully made new user assignments.'

    post '/projects/2/users',
      {assigned_users: [ '2!project_manager', '4!quality_assurance' ]},
      pm_session

    assert_equal 302, last_response.status
    assert_equal success, session[:success]

    get last_response['Location']
    assert_includes last_response.body, 'Project Assignment'
    assert_includes last_response.body, 'finance manager'
    assert_includes last_response.body, 'Assign Users to Project'
    assert_includes last_response.body, %q(type="submit">Change User Assignments)

    get '/projects/2', {}, pm_session

    assert_includes last_response.body, 'Project Manager Demo'
    refute_includes last_response.body, 'Developer Demo'
    assert_includes last_response.body, 'Quality Assurance Demo'

    post '/projects/1/users', {}, pm_session

    assert_equal 302, last_response.status
    assert_equal error, session[:error]
  end

  # view project details
  def test_get_projects_id
    get '/projects/1', {}, admin_session

    assert_role('Admin')
    assert_includes last_response.body, 'Assign Users'
    assert_includes last_response.body, %q(s7-edit"></i> Edit)
    assert_includes last_response.body, 'Create New Ticket'

    assert_includes last_response.body, 'Project ID: #1'
    assert_includes last_response.body, 'Tickets Overview'
    assert_includes last_response.body, 'Assigned Users'
    assert_includes last_response.body, 'Project Tickets'

    assert_includes last_response.body, 'Project Manager Demo'
    assert_includes last_response.body, 'Quality Assurance Demo'

    get '/projects/3', {}, pm_session
    
    assert_role('Project Manager')
    assert_includes last_response.body, 'Assign Users'
    assert_includes last_response.body, %q(s7-edit"></i> Edit)
    assert_includes last_response.body, 'Create New Ticket'

    assert_includes last_response.body, 'Project Manager Demo'
    refute_includes last_response.body, 'Developer Demo'
    assert_includes last_response.body, 'Quality Assurance Demo'

    get '/projects/2', {}, dev_session

    assert_role('Developer')

    refute_includes last_response.body, 'Assign Users'
    refute_includes last_response.body, %q(s7-edit"></i> Edit)
    assert_includes last_response.body, 'Create New Ticket'

    assert_includes last_response.body, 'Admin Demo'
    assert_includes last_response.body, 'Developer Demo'
    refute_includes last_response.body, 'Quality Assurance Demo'

    get '/projects/3', {}, qa_session

    assert_role('Quality Assurance')
    refute_includes last_response.body, 'Assign Users'
    refute_includes last_response.body, %q(s7-edit"></i> Edit)
    assert_includes last_response.body, 'Create New Ticket'
  end

  # post project edits
  def post_get_project_id
    error ='That project name is already in use. A project name must be unique.'

    post '/projects/2',
         {name: 'bugtracker', description: 'valid desc'},
         pm_session

    assert_equal 302, last_response.status
    assert_equal 'error', session[:error]

    get last_response['Location']
    assert_equal 200, last_response.status
    assert_includes last_response.body, 'Project Details'
    assert_includes last_response.body, 'Project ID: #2'

    post '/projects/1',
         {name: 'pig tracker', description: 'app for tracking pigs and piglets'},
         pm_session

    assert_equal 302, last_response.status
    assert_equal 'You have successfully updated the project.', session[:success]

    get last_response['Location']
    assert_includes last_response.body, 'pig tracker'
    assert_includes last_response.body, 'app for tracking pigs and piglets'
    assert_includes last_response.body, 'Project ID: #1'
  end

# # -------------TICKETS-------------------------------------------------------- #
# # -------------TICKETS-------------------------------------------------------- #
# # -------------TICKETS-------------------------------------------------------- #
# # -------------TICKETS-------------------------------------------------------- #
# # -------------TICKETS-------------------------------------------------------- #
# # -------------TICKETS-------------------------------------------------------- #

  # view all tickets brought up dynamically for logged in user
  def test_get_tickets
    get '/tickets', {}, admin_session

    assert_role('Admin')
    assert_includes last_response.body, 'Tickets Overview'
    assert_includes last_response.body, 'Unresolved Tickets'
    assert_includes last_response.body, 'Resolved Tickets'
    assert_includes last_response.body, 'My Submitted Tickets'
    assert_includes last_response.body, 'Create New Ticket'
    assert_includes last_response.body, 'View'

    get '/tickets', {}, pm_session
    
    assert_role('Project Manager')

    get '/tickets', {}, dev_session
    assert_includes last_response.body, 'Tickets Overview'
    assert_includes last_response.body, 'Unresolved Tickets'
    assert_includes last_response.body, 'View'

    assert_role('Developer')
    assert_includes last_response.body, 'Tickets Overview'
    assert_includes last_response.body, 'Resolved Tickets'
    assert_includes last_response.body, 'View'

    get '/tickets', {}, qa_session

    assert_role('Quality Assurance')
    assert_includes last_response.body, 'Tickets Overview'
    assert_includes last_response.body, 'Create New Ticket'
    assert_includes last_response.body, 'View'
  end

  # see ticket details
  def test_get_ticket_id
    # ticket 2
    # Ticket.create(@test_db, ['In Progress', 'Object models',
    #                          'models for all database handling',
    #                          'Feature Request', 'High', 2, 1, 3])
    create_dummy_comment(4, 2)

    get '/tickets/2', {}, admin_session

    assert_role('Admin')
    assert_includes last_response.body, 'Ticket Details'
    assert_includes last_response.body, 'Object models'
    assert_includes last_response.body, 'Ticket ID: #2'
    assert_includes last_response.body, 'In Progress'
    assert_includes last_response.body, 'High'
    assert_includes last_response.body, 'Add Attachment'
    assert_includes last_response.body, 'Edit'
    assert_includes last_response.body, 'Assigned Developer'
    assert_includes last_response.body, 'Attachments'
    assert_includes last_response.body, 'Ticket Update History'
    assert_includes last_response.body, 'Post Comment'

    get '/tickets/2', {}, pm_session
    
    assert_role('Project Manager')
    assert_includes last_response.body, 'Ticket ID: #2'
    assert_includes last_response.body, 'Add Attachment'
    assert_includes last_response.body, 'Edit'
    assert_includes last_response.body, 'Assigned Developer'

    get '/tickets/2', {}, dev_session

    assert_role('Developer')
    assert_includes last_response.body, 'Ticket ID: #2'
    assert_includes last_response.body, 'Add Attachment'
    assert_includes last_response.body, 'Edit'
    refute_includes last_response.body, 'Assigned Developer'

    get '/tickets/2', {}, qa_session

    assert_role('Quality Assurance')
    assert_includes last_response.body, 'Ticket ID: #2'
    assert_includes last_response.body, 'Add Attachment'
    assert_includes last_response.body, 'Edit'
    refute_includes last_response.body, 'Assigned Developer'
    assert_includes last_response.body,
      'This message is for testing purposes only.'
  end

  # post a new ticket
  def test_post_tickets_new
    success = 'You have successfully submitted a new ticket.'

    post '/tickets/new',
         {title: 'testing new ticket 5790238',
          description: 'testing post tickets route',
          type: 'Others', priority: 'Low', project_id: 3},
         dev_session

    assert_equal 302, last_response.status
    assert_equal success, session[:success]

    get last_response['Location']
    assert_equal 200, last_response.status

    assert_nil session[:success]
    assert_includes last_response.body, 'testing new ticket 5790238'
  end

  # post a new ticket from project details view
  def test_post_tickets_new_from_project_details
    success = 'You have successfully submitted a new ticket.'

    post '/tickets/new/from-project',
         {title: 'testing new ticket 5790238',
          description: 'testing post tickets route',
          type: 'Others', priority: 'Low', project_id: 3},
         qa_session

    assert_equal 302, last_response.status
    assert_equal success, session[:success]

    get last_response['Location']
    assert_equal 200, last_response.status

    assert_nil session[:success]
    assert_includes last_response.body, 'testing new ticket 5790238'
  end
  
  # edit ticket properties
  def test_post_ticket_edits
    # ticket 1
    # Ticket.create(@test_db, ['Open', 'Unable to login',
    #                          'Create a login functionality',
    #                          'Bug/Error Report', 'Low', 4, 3, 1])
    post '/tickets/1',
         {status: 'Add. Info Required', title: 'frontend/css',
            description: 'integrate bootstrap/css', type: 'Service Request',
            priority: 'Critical', developer_id: '3'},
         pm_session

    assert_equal 302, last_response.status
    assert_equal 'You have successfully made change(s) to a ticket.',
                 session[:success]

    get last_response['Location']
    assert_includes last_response.body, 'frontend/css'
    assert_includes last_response.body, 'Critical'
    assert_includes last_response.body, 'integrate bootstrap/css'
    assert_includes last_response.body, 'Add. Info Required'
    assert_includes last_response.body, 'Service Request'
    assert_includes last_response.body, 'Critical'
    assert_includes last_response.body, %q(ASSIGNED TO</span>)
    assert_includes last_response.body, 'Assigned Developer'
    assert_includes last_response.body, 'Ticket Status'
  end

  # post a ticket comment
  def test_post_ticket_id_comment_valid
    post '/tickets/2/comment',
         {comment: 'This is a test. Do not be alarmed.'},
         dev_session

    assert_equal 302, last_response.status
    get last_response['Location']
    assert_includes last_response.body, 'This is a test. Do not be alarmed.'
  end
end