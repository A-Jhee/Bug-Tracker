# require "simplecov"
# SimpleCov.start

ENV["RACK_ENV"] = "test"

require "minitest/autorun"
require "minitest/reporters"
require "rack/test"

MiniTest::Reporters.use!

require_relative "../bugtracker"
require_relative "../database_persistence"

class BugtrackerTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def setup
    @test_db = DatabasePersistence.new("bugtrack_test")
    sql = <<~SQL
    TRUNCATE projects,
             projects_users_assignments,
             tickets,
             ticket_comments,
             ticket_update_history,
             ticket_attachments
             RESTART IDENTITY;
    SQL
    @test_db.query(sql)
    
    create_dummy_projects
    create_dummy_tickets
  end

  def teardown
    @test_db.disconnect
  end

  def session
    last_request.env["rack.session"]
  end

  # ----- HELPER METHODS ----- #

  def logout
    session.clear
  end

  def create_dummy_projects
    # project 1
    @test_db.create_project('bugtracker', 'WebApp built on PSQL to submit/track bug reports during software development')
    # project 2
    @test_db.create_project('finance manager', 'Personal finance manager to budgeting and record keeping')
  end

  def create_dummy_tickets
    # ticket 1
    @test_db.create_ticket('Open', 'Unable to login',
      'Create a login functionality with 4 demo logins',
      'Feature Request', 'Low', 4, 1, 3)
    # ticket 2
    @test_db.create_ticket('Resolved', 'Object model to handle database',
      'Create an DatabasePersistence.rb file for all database handling',
      'Feature Request', 'High', 4, 1, 3)
    # ticket 3
    @test_db.create_ticket('In Progress', 'Test suite',
      'Create a test suite to test all the routes so far',
      'Service Request', 'High', 4, 1, 3)
    # ticket 4
    @test_db.create_ticket('Open', 'Finance manager roadmap',
      'Draw up a rough draft for finance manager app roadmap',
      'Other', 'Low', 4, 2, 3)
  end

  def create_dummy_ticket_comments(ticket_id)
    comment = "This message is for testing purposes only."
    commenter_id = 4
    @test_db.create_comment(comment, commenter_id, ticket_id)
  end

  def delete_test_user
    sql = <<~SQL 
      DELETE FROM users
            WHERE name = 'George Washington'
              AND email = 'gwash@potus.gov';
    SQL
    @test_db.query(sql)
  end

  # ----- END OF HELPER METHODS ----- #

  # def test_welcome_message_and_role
  #   get "/dashboard"

  #   assert_equal 200, last_response.status
  #   assert_includes last_response.body, "DEMO_QualityAssurance"
  #   assert_includes last_response.body, "quality_assurance"
  # end

  def test_dashboard_redirect
    get "/"
    
    assert_equal 302, last_response.status

    get last_response["Location"]
    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]
    assert_includes last_response.body, "<h2>Welcome,"
    assert_includes last_response.body, "<h2>You are logged in as"
    assert_includes last_response.body, "Dashboard"
    assert_includes last_response.body, "My Projects"
    assert_includes last_response.body, "My Tickets"
  end

  def test_get_projects
    get "/projects"

    assert_equal 200, last_response.status
    assert_includes last_response.body, "bugtracker"
    assert_includes last_response.body, "finance manager"
    assert_includes last_response.body, "Personal finance manager to budgeting"
    assert_includes last_response.body, "Create A Ticket"
  end

  def test_get_tickets
    get "/tickets"

    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]
    assert_includes last_response.body, %q(href="/tickets/new/")
    assert_includes last_response.body, "Edit/Assign"
    assert_includes last_response.body, "Details"
    assert_includes last_response.body, "Title"
    assert_includes last_response.body, "Project Name"
    assert_includes last_response.body, "Developer Assigned"
    assert_includes last_response.body, "Ticket Priority"
    assert_includes last_response.body, "Ticket Status"
    assert_includes last_response.body, "Ticket Type"
    assert_includes last_response.body, "Created On"
    assert_includes last_response.body, "DEMO_Developer"

    assert_includes last_response.body, 'Unable to login'
    assert_includes last_response.body, 'Object model to handle database'
    assert_includes last_response.body, 'Test suite'
    assert_includes last_response.body, 'Finance manager roadmap'
  end

  def test_get_tickets_new
    get "/tickets/new/"

    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]
    assert_includes last_response.body, %q(<select name="project_id")
    assert_includes last_response.body, "Ticket Priority"
    assert_includes last_response.body, "Ticket Type"
    assert_includes last_response.body, "Title"
    assert_includes last_response.body, "Description"
    assert_includes last_response.body, %q(<input type="text" name="description")
    assert_includes last_response.body, "Back to Tickets List"
    assert_includes last_response.body, %q(<button type="submit")
  end

  def test_post_tickets_new
    post "/tickets/new/", {title: 'testing new ticket', 
      description: 'testing post tickets route', 
      type: 'Others', priority: 'Low', project_id: 1}

    assert_equal 302, last_response.status
    assert_equal "You have successfully submitted a new ticket.", session[:success]

    get last_response["Location"]
    assert_equal 200, last_response.status
    assert_nil session[:success]
    assert_includes last_response.body, 'testing new ticket'
    assert_includes last_response.body, 'Others'
  end

  def test_post_tickets_new_with_invalid_title
    post "/tickets/new/", {title: '     ', 
      description: 'testing post tickets route', 
      type: 'Other', priority: 'High', project_id: 2}

    assert_equal 200, last_response.status
    assert_includes last_response.body, "Ticket title must be between 1 and 100 characters."
    assert_includes last_response.body, "High"
    assert_includes last_response.body, "Other"
    assert_includes last_response.body, "finance manager"
    assert_includes last_response.body, "     "
  end

  def test_post_tickets_new_with_invalid_description
    post "/tickets/new/", {title: 'test_title', 
      description: '     ', 
      type: 'Other', priority: 'High', project_id: 2}

    assert_equal 200, last_response.status
    assert_includes last_response.body, "Description must be between 1 and 300 characters."
    assert_includes last_response.body, "High"
    assert_includes last_response.body, "Other"
    assert_includes last_response.body, "finance manager"
    assert_includes last_response.body, "     "
    assert_includes last_response.body, "test_title"
  end

  def test_get_tickets_new_project_id
    get "/tickets/new/1"

    assert_equal 200, last_response.status
    assert_includes last_response.body, %q(<h3>"bugtracker")
    assert_includes last_response.body, %q(<input type="hidden" name="project_id" value="1")
    assert_includes last_response.body, %q(<button type="submit")

    get "/tickets/new/2"

    assert_equal 200, last_response.status
    assert_includes last_response.body, %q(<h3>"finance manager")
    assert_includes last_response.body, %q(<input type="hidden" name="project_id" value="2")
    assert_includes last_response.body, "Back to Tickets List"
    assert_includes last_response.body, %q(<button type="submit")
  end

  def test_get_tickets_id_edit
    # ticket id: 3 = ('In Progress', 'Test suite',
      # 'Create a test suite to test all the routes so far',
      # 'Service Request', 'High', 4, 1, 3)

    get "/tickets/3/edit"

    assert_equal 200, last_response.status
    assert_includes last_response.body, "Test suite"
    assert_includes last_response.body, "Create a test suite to test all the routes so far"
    assert_includes last_response.body, %q(<option selected="selected">High)
    assert_includes last_response.body, %q(<option selected="selected">In Progress)
    assert_includes last_response.body, %q(<option selected="selected">Service Request)
    assert_includes last_response.body, %q(<option value="3" selected="selected">DEMO_Developer)
    assert_includes last_response.body, %q(action="/tickets/3">)
    assert_includes last_response.body, "Back to Tickets List"
    assert_includes last_response.body, %q(<button type="submit">Update Ticket)

    # ticket id: 4 = ('Open', 'Finance manager roadmap',
    #   'Draw up a rough draft for finance manager app roadmap',
    #   'Other', 'Low', 4, 2, 3)

    get "/tickets/4/edit"

    assert_equal 200, last_response.status
    assert_includes last_response.body, "Finance manager roadmap"
    assert_includes last_response.body, "Draw up a rough draft for finance manager app roadmap"
    assert_includes last_response.body, %q(<option selected="selected">Low)
    assert_includes last_response.body, %q(<option selected="selected">Open)
    assert_includes last_response.body, %q(<option selected="selected">Other)
    assert_includes last_response.body, %q(<option value="3" selected="selected">DEMO_Developer)
    assert_includes last_response.body, %q(action="/tickets/4">)
    assert_includes last_response.body, "Back to Tickets List"
    assert_includes last_response.body, %q(<button type="submit">Update Ticket)
  end

  def test_post_tickets_id_without_edits
    post "/tickets/4", {title: "Finance manager roadmap",
                         description: "Draw up a rough draft for finance manager app roadmap",
                         priority: "Low", status: "Open", type: "Other", 
                         developer_id: "3"}

    assert_equal 302, last_response.status
    assert_equal "You did not make any changes. \
         Make any changes to this ticket, or you can return back to Tickets list.",
         session[:error]

    get last_response["Location"]
    assert_includes last_response.body, "Finance manager roadmap"
    assert_includes last_response.body, %q(<option selected="selected">Low)
    assert_includes last_response.body, %q(<option selected="selected">Open)
    assert_includes last_response.body, %q(<option selected="selected">Other)
    assert_includes last_response.body, %q(<option value="3" selected="selected">DEMO_Developer)
  end

  def test_post_tickets_id_with_edits
    post "/tickets/4", {title: "Finance manager roadmap",
                         description: "Draw up a rough draft for finance manager app roadmap",
                         priority: "Critical", status: "Add. Info Required", 
                         type: "Bug/Error Report", developer_id: "5"}

    assert_equal 302, last_response.status
    assert_equal "You have successfully made changes to a ticket.", session[:success]

    get last_response["Location"]
    assert_includes last_response.body, "Critical"
    assert_includes last_response.body, "Add. Info Required"
    assert_includes last_response.body, "Bug/Error Report"
    assert_includes last_response.body, "TEST_Developer"
  end

  def test_post_tickets_id_with_invalid_title
    post "/tickets/4", {title: "     ",
                         description: "Draw up a rough draft for finance manager app roadmap",
                         priority: "Critical", status: "Add. Info Required", type: "Bug/Error Report", 
                         developer_id: "5"}

    assert_equal 200, last_response.status
    assert_includes last_response.body, "Make changes to ticket properties"
    assert_includes last_response.body, "Ticket title must be between 1 and 100 characters."
    assert_includes last_response.body, "Critical"
    assert_includes last_response.body, "Bug/Error Report"
    assert_includes last_response.body, "Add. Info Required"
    assert_includes last_response.body, "     "
    assert_includes last_response.body, "TEST_Developer"
  end

  def test_post_tickets_id_with_invalid_description
    post "/tickets/4", {title: "Finance manager roadmap",
                         description: "     ",
                         priority: "Critical", status: "Add. Info Required", type: "Bug/Error Report", 
                         developer_id: "5"}

    assert_equal 200, last_response.status
    assert_includes last_response.body, "Make changes to ticket properties"
    assert_includes last_response.body, "Description must be between 1 and 300 characters."
    assert_includes last_response.body, "     "
  end

  def test_update_ticket_history_within_tickets_edit
    # old ticket id: 4 = ('Open', 'Finance manager roadmap',
    #   'Draw up a rough draft for finance manager app roadmap',
    #   'Other', 'Low', 4, 2, 3)

    post "/tickets/4", {title: "Finance manager roadmap",
                         description: "Draw up a rough draft for finance manager app roadmap",
                         priority: "Critical", status: "Add. Info Required", 
                         type: "Bug/Error Report", developer_id: "5"}

    assert_equal 302, last_response.status

    assert_equal "You have successfully made changes to a ticket.", session[:success]

    get last_response["Location"]

    assert_equal 200, last_response.status
    assert_includes last_response.body, "Ticket Details"
    assert_includes last_response.body, "Critical"
    assert_includes last_response.body, "Add. Info Required"
    assert_includes last_response.body, "TEST_Developer"
  end

  def test_post_delete_ticket
    # ticket 1 ('Open', 'Unable to login',
      # 'Create a login functionality with 4 demo logins',
      # 'Feature Request', 'Low', 4, 1, 3)

    post "/tickets/1/destroy"

    assert_equal 302, last_response.status
    assert_equal "The ticket has been deleted.", session[:success]

    get last_response["Location"]
    assert_equal 200, last_response.status
    refute_includes last_response.body, "Unable to login"
    refute_includes last_response.body, "Create a login functionality with 4 demo logins"
  end

  # see ticket details
  def test_get_ticket_id
    # ticket 2 ('Resolved', 'Object model to handle database',
      # 'Create an DatabasePersistence.rb file for all database handling',
      # 'Feature Request', 'High', 4, 1, 3)

    create_dummy_ticket_comments(2)

    get "/tickets/2"

    assert_equal 200, last_response.status

    # Checking for ticket details
    assert_includes last_response.body, "Ticket Details"
    assert_includes last_response.body, "Object model to handle database"
    assert_includes last_response.body, "ASSIGNED DEVELOPER"
    assert_includes last_response.body, "DEMO_Developer"
    assert_includes last_response.body, "UPDATED ON"

    # Checking for comment section
    assert_includes last_response.body, "Leave your comments here."
    assert_includes last_response.body, %q(<button type="submit">Add Comment)
    assert_includes last_response.body, "This message is for testing purposes only."
  end

  # post a ticket comment
  def test_post_ticket_id_comment_valid
    post "/tickets/2/comment", {comment: "This is a test. Do not be alarmed."}

    assert_equal 302, last_response.status
    get last_response["Location"]
    assert_includes last_response.body, "This is a test. Do not be alarmed."
    assert_includes last_response.body, "DEMO_QualityAssurance"
  end

  # post a ticket comment with invalid entry
  def test_post_ticket_id_comment_invalid
    post "/tickets/2/comment", {comment: "      "}

    assert_equal 200, last_response.status
    assert_includes last_response.body, "Comment must be between 1 and 300 characters."
    assert_includes last_response.body, "      "
  end

  # delete a ticket comment
  def test_post_ticket_id_comment_commentId_destroy
    create_dummy_ticket_comments(2)

    post "/tickets/2/comment/1/destroy"

    assert_equal 302, last_response.status
    assert_equal "The ticket comment has been deleted.", session[:success]

    get last_response["Location"]
    assert_includes last_response.body, "Ticket Details"
  end

  # render new project form
  def test_get_projects_new
    get "/projects/new"

    assert_equal 200, last_response.status
    assert_includes last_response.body, "Create Project"
    assert_includes last_response.body, "Project Name"
    assert_includes last_response.body, "Description"
    assert_includes last_response.body, %q(<button type="submit">Create Project)
  end

  # post a new project with invalid entries: bad name, bad description, not unique name
  def test_post_projects_new_invalid
    post "/projects/new", {name: "    ", description: ""}

    assert_equal 200, last_response.status
    assert_includes last_response.body, "Project name must be between 1 and 100 characters."
    assert_includes last_response.body, "    "

    post "/projects/new", {name: "test project", description: "     "}

    assert_equal 200, last_response.status
    assert_includes last_response.body, "Description must be between 1 and 300 characters."
    assert_includes last_response.body, "     "

    post "/projects/new", {name: "bugtracker", description: "valid description"}

    assert_equal 200, last_response.status
    assert_includes last_response.body, "That project name is already in use. A project name must be unique."
    assert_includes last_response.body, "bugtracker"
  end

  # post a new project with valid entries
  def test_post_projects_new_valid
    post "/projects/new", {name: "test project", description: "valid description"}

    assert_equal 302, last_response.status
    assert_equal "You have successfully submitted a new project.", session[:success]

    get last_response["Location"]
    assert_includes last_response.body, "test project"
    assert_includes last_response.body, "valid description"
  end

  # render project edit form
  def get_project_id_edit
    get "/projects/1/edit"

    assert_equal 200, last_response.status
    assert_includes last_response.body, "Edit Project"
    assert_includes last_response.body, "bugtracker"
  end

  # post project edits
  def post_get_project_id
    post "/projects/1", {name: "    ", description: ""}

    assert_equal 200, last_response.status
    assert_includes last_response.body, "Project name must be between 1 and 100 characters."
    assert_includes last_response.body, "    "

    post "/projects/1", {name: "test project", description: "     "}

    assert_equal 200, last_response.status
    assert_includes last_response.body, "Description must be between 1 and 300 characters."
    assert_includes last_response.body, "     "

    post "/projects/1", {name: "bugtracker", description: "valid description"}

    assert_equal 200, last_response.status
    assert_includes last_response.body, "That project name is already in use. A project name must be unique."
    assert_includes last_response.body, "bugtracker"

    post "/projects/1", {name: "pig tracker", description: "app for tracking pigs and piglets"}

    assert_equal 302, last_response.status
    assert_equal "You have successfully updated the project.", session[:success]

    get last_response["Location"]
    assert_includes last_response.body, "pig tracker"
    assert_includes last_response.body, "app for tracking pigs and piglets"
  end

  # render assign users form
  def test_get_projects_id_users
    get "/projects/1/users"

    assert_equal 200, last_response.status
    assert_includes last_response.body, "Assign"
    assert_includes last_response.body, "bugtracker"
    assert_includes last_response.body, "Select users you wish to assign to this project"
    assert_includes last_response.body, "DEMO_Admin"
    assert_includes last_response.body, %q(<input type="checkbox")
  end

  # post new user assignments to a project
  def test_post_projects_id_users
    ["1", "2", "3"].each { |ticket_id| @test_db.delete_ticket(ticket_id) }

    post "/projects/1/users",
      {assigned_users: ["2!DEMO_ProjectManager", "3!DEMO_Developer", "5!TEST_Developer"]}

    assert_equal 302, last_response.status
    assert_equal "You have successfully made new user assignments.", session[:success]

    get last_response["Location"]
    assert_includes last_response.body, "Edit Project"
    assert_includes last_response.body, "DEMO_ProjectManager"
    assert_includes last_response.body, "DEMO_Developer"
    assert_includes last_response.body, "TEST_Developer"

    refute_includes last_response.body, "DEMO_QualityAssurance"

    post "/projects/1/users",
      {assigned_users: ["1!DEMO_Admin", "3!DEMO_Developer", "4!DEMO_QualityAssurance"]}

    assert_equal 302, last_response.status

    get last_response["Location"]
    assert_includes last_response.body, "Edit Project"
    assert_includes last_response.body, "DEMO_Admin"
    assert_includes last_response.body, "DEMO_Developer"
    assert_includes last_response.body, "DEMO_QualityAssurance"

    refute_includes last_response.body, "TEST_Developer"

    post "/projects/1/users"

    assert_equal 302, last_response.status
    assert_equal "There are no users assigned to this project.", session[:success]

    get last_response["Location"]

    assert_includes last_response.body, "Edit Project"

    refute_includes last_response.body, "TEST_Developer"
    refute_includes last_response.body, "DEMO_Developer"
  end

  # render register new user form
  def test_get_register
    get "/logout"

    get "/register"

    assert_equal 200, last_response.status
    assert_includes last_response.body, "E-mail"
    assert_includes last_response.body, "Password"
    assert_includes last_response.body, "Already have an account?"
    assert_includes last_response.body, "Register"
    assert_includes last_response.body, %q(<button type="submit")
  end

  # post an invalid register new user form
  def test_post_register_invalid
    get "/logout"

    # bad email: existing email - testdev@demonstration.com
    post "/register", {first_name: "George", last_name: "Washington",
                       email: "testdev@demonstration.com", username: "g-wash",
                       password: "imthefirst1"}

    assert_equal 200, last_response.status
    assert_includes last_response.body, "That username or email is already in use."
    assert_includes last_response.body, "Already have an account?"
    assert_includes last_response.body, "Register"
    assert_includes last_response.body, %q(<button type="submit")

    # bad username: existing username - admin
    post "/register", {first_name: "George", last_name: "Washington",
                       email: "gwash@potus.gov", username: "admin",
                       password: "imthefirst1"}

    assert_equal 200, last_response.status
    assert_includes last_response.body, "That username or email is already in use."
    assert_includes last_response.body, "Already have an account?"
    assert_includes last_response.body, "Register"
    assert_includes last_response.body, %q(<button type="submit")
  end

  # post an valid register new user form
  def test_post_register_valid
    get "/logout"
    delete_test_user

    post "/register", {first_name: "George", last_name: "Washington",
                       email: "gwash@potus.gov", username: "g-wash",
                       password: "imthefirst1"}

    assert_equal 302, last_response.status
    assert_equal "You are now logged in to your new account, George Washington.", session[:success]
    assert_equal "George Washington", session[:user_name]
    assert_equal "Unassigned", session[:user_role]
    assert(session[:user_id])

    get last_response["Location"]

    assert_includes last_response.body, "Welcome,"
    assert_includes last_response.body, "You are logged in as"
  end

  # render login form
  def test_get_login
    get "/logout"

    get "/login"

    assert_equal 200, last_response.status
    assert_includes last_response.body, "Username"
    assert_includes last_response.body, "Password"
    assert_includes last_response.body, "Don't have an account?"
    assert_includes last_response.body, "Log In"
    assert_includes last_response.body, %q(<button type="submit")
  end

  def test_login_invalid
    get "/logout"

    # correct username, wrong password
    post "/login", {username: 'admin', password: 'wrongpassword'}

    assert_equal 200, last_response.status
    assert_includes last_response.body, "Username or password was incorrect."
    assert_includes last_response.body, "Don't have an account?"
    assert_includes last_response.body, "Log In"
    assert_includes last_response.body, %q(<button type="submit")

    # wrong username, correct password
    post "/login", {username: 'admin_not', password: 'admin1admin1'}

    assert_equal 200, last_response.status
    assert_includes last_response.body, "Username or password was incorrect."
    assert_includes last_response.body, "Don't have an account?"
    assert_includes last_response.body, "Log In"
    assert_includes last_response.body, %q(<button type="submit")
  end

  def test_login_valid
    get "/logout"

    post "/login", {username: 'pm', password: 'pm1pm1pm1'}

    assert_equal 302, last_response.status
    assert_equal "You are now logged in as Project Manager, DEMO_ProjectManager.", session[:success]
    assert_equal "DEMO_ProjectManager", session[:user_name]
    assert_equal "Project Manager", session[:user_role]
    assert_equal "2", session[:user_id]

    get last_response["Location"]

    assert_includes last_response.body, "Welcome,"
    assert_includes last_response.body, "You are logged in as"
  end
end