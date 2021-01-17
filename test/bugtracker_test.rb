ENV["RACK_ENV"] = "test"

require "minitest/autorun"
require "minitest/reporters"
require "rack/test"
# require "pg"

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

  def test_welcome_message_and_role
    get "/dashboard"

    assert_equal 200, last_response.status
    assert_includes last_response.body, "DEMO_QualityAssurance"
    assert_includes last_response.body, "quality_assurance"
  end

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
    assert_includes last_response.body, %q(href="/tickets/new")
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
    get "/tickets/new"

    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]
    assert_includes last_response.body, "Project"
    assert_includes last_response.body, "Ticket Priority"
    assert_includes last_response.body, "Ticket Type"
    assert_includes last_response.body, "Title"
    assert_includes last_response.body, "Description"
    assert_includes last_response.body, %q(<input type="text" name="description")
    assert_includes last_response.body, "Back to Tickets List"
    assert_includes last_response.body, %q(<button type="submit")
  end

  def test_post_tickets_new
    post "/tickets", {title: 'testing new ticket', 
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
    post "/tickets", {title: '     ', 
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
    post "/tickets", {title: 'test_title', 
      description: '     ', 
      type: 'Other', priority: 'High', project_id: 2}

    assert_equal 200, last_response.status
    assert_includes last_response.body, "Ticket description must be between 1 and 300 characters."
    assert_includes last_response.body, "High"
    assert_includes last_response.body, "Other"
    assert_includes last_response.body, "finance manager"
    assert_includes last_response.body, "     "
    assert_includes last_response.body, "test_title"
  end

  def test_get_tickets_new_project_id
    get "/tickets/new/1"

    assert_equal 200, last_response.status
    assert_includes last_response.body, %q(<dd>"bugtracker")
    assert_includes last_response.body, %q(<input type="hidden" name="project_id" value="1")
    assert_includes last_response.body, %q(<button type="submit")

    get "/tickets/new/2"

    assert_equal 200, last_response.status
    assert_includes last_response.body, %q(<dd>"finance manager")
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
    assert_equal "You did not make any changes. Make any changes to this ticket, or you can return back to Tickets list.", session[:error]

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
    assert_includes last_response.body, "Ticket description must be between 1 and 300 characters."
    assert_includes last_response.body, "     "
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
end