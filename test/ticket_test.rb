# require "simplecov"
# SimpleCov.start

require 'minitest/autorun'
require 'minitest/reporters'
require 'pg'
require 'date'

MiniTest::Reporters.use!

require_relative '../models/ticket'
require_relative '../models/project'

class TicketTest < Minitest::Test
  def setup
    @db = PG.connect(dbname: 'bugtrack_test')

    sql = <<~SQL
    TRUNCATE projects,
             projects_users_assignments,
             tickets,
             ticket_comments,
             ticket_update_history,
             ticket_attachments
             RESTART IDENTITY;
    SQL
    @db.exec(sql)

    @today = Date.today.iso8601

    Project.create(@db, 'bugtracker', 'WebApp built on PSQL to track bug')
    Project.create(@db, 'finance manager', 'Personal finance/budget manager')
    Project.create(@db, 'text editor', 'simple text editor')

    Ticket.create(@db, ['Open', 'Unable to login',
                        'Create a login functionality',
                        'Bug/Error Report', 'Low', 4, 3, 1])
    @ticket1 = Ticket.new(@db, '1')

    Ticket.create(@db, ['In Progress', 'Object models',
                        'models for all database handling',
                        'Feature Request', 'High', 2, 1, 3])
    @ticket2 = Ticket.new(@db, '2')

    Ticket.create(@db, ['Resolved', 'Test suite',
                        'Create test suites for all',
                        'Service Request', 'Critical', 1, 2, 2])
    @ticket3 = Ticket.new(@db, '3')
  end

  def teardown
    @db.close
  end

  def test_new
    assert_equal '1', @ticket1.id
    assert_equal 'Open', @ticket1.status
    assert_equal 'Unable to login', @ticket1.title
    assert_equal 'Create a login functionality', @ticket1.description
    assert_equal 'Bug/Error Report', @ticket1.type
    assert_equal 'Low', @ticket1.priority
    assert_equal '4', @ticket1.submitter_id
    assert_equal 'Quality Assurance Demo', @ticket1.submitter_name
    assert_equal '3', @ticket1.project_id
    assert_equal 'text editor', @ticket1.project_name
    assert_equal '1', @ticket1.developer_id
    assert_equal 'Admin Demo', @ticket1.developer_name
    assert_equal @today, @ticket1.created_on[0, 10]
    assert_equal @today, @ticket1.updated_on[0, 10]
  end

  def test_Ticket_create
    Ticket.create(@db, ['In Progress', 'Ticket.create test',
                        'test desc', 'Bug/Error Report', 'Criticial',
                        '2', '1', '3'])
    sql = "SELECT * FROM tickets WHERE title='Ticket.create test';"
    result = @db.exec(sql).first

    assert_equal 'In Progress', result['status']
    assert_equal 'Ticket.create test', result['title']
    assert_equal 'test desc', result['description']
    assert_equal 'Bug/Error Report', result['type']
    assert_equal 'Criticial', result['priority']
    assert_equal '2', result['submitter_id']
    assert_equal '1', result['project_id']
    assert_equal '3', result['developer_id']

    sql = "DELETE FROM tickets WHERE title='Ticket.create test';"
    @db.exec(sql)
  end

  def test_Ticket_all
    result = Ticket.all(@db)

    assert_equal 3, result.ntuples

    all_tickets = result.sort { |a, b| a['id'].to_i <=> b['id'].to_i }

    assert_equal '1', all_tickets[0]['id']
    assert_equal 'Unable to login', all_tickets[0]['title']
    assert_equal 'Open', all_tickets[0]['status']
    assert_equal 'Low', all_tickets[0]['priority']

    assert_equal '2', all_tickets[1]['id']
    assert_equal 'Object models', all_tickets[1]['title']
    assert_equal 'In Progress', all_tickets[1]['status']
    assert_equal 'High', all_tickets[1]['priority']

    assert_equal '3', all_tickets[2]['id']
    assert_equal 'Test suite', all_tickets[2]['title']
    assert_equal 'Resolved', all_tickets[2]['status']
    assert_equal 'Critical', all_tickets[2]['priority']
  end

  def test_Ticket_all_for
    result = Ticket.all_for(@db, '2').first

    assert_equal '3', result['id']
    assert_equal 'Test suite', result['title']
    assert_equal 'finance manager', result['project_name']
    assert_equal 'Project Manager Demo', result['dev_name'] 
  end

  def test_Ticket_last_3days
    result = Ticket.last_3days(@db)
    sorted_tickets = result.sort { |a, b| a['id'].to_i <=> b['id'].to_i }

    assert_equal '1', sorted_tickets[0]['id']
    assert_equal '2', sorted_tickets[1]['id']
    assert_equal '3', sorted_tickets[2]['id']
  end

  def test_Ticket_last_3days_for
    result = Ticket.last_3days_for(@db, '1').first

    assert_equal '2', result['id']
    assert_equal 'Object models', result['title']
    assert_equal 'bugtracker', result['project_name']
    assert_equal 'Developer Demo', result['dev_name']
  end

  def test_Ticket_open_count
    assert_equal '1', Ticket.open_count(@db, @today).first['count']
  end

  def test_Ticket_open_count_for
    assert_equal '1', Ticket.open_count_for(@db, @today, '3').first['count']
    assert_nil Ticket.open_count_for(@db, @today, '1').first
  end

  def test_Ticket_resolved_count
    assert_equal '1', Ticket.resolved_count(@db, @today).first['count']
  end

  def test_Ticket_resolved_count_for
    assert_equal '1', Ticket.resolved_count_for(@db, @today, '2').first['count']
    assert_nil Ticket.resolved_count_for(@db, @today, '1').first
  end

  def test_Ticket_create_comment_and_get_comments
    Ticket.create_comment(@db, 'needs 4 login roles', '2', '1')
    Ticket.create_comment(@db, 'I predict 4 model total', '3', '2')
    Ticket.create_comment(@db, 'all finished', '4', '3')

    result = @ticket1.comments(@db).first
    assert_equal '1', result['ticket_id']
    assert_equal 'Project Manager Demo', result['commenter']
    assert_equal 'needs 4 login roles', result['message']

    result = @ticket2.comments(@db).first
    assert_equal '2', result['ticket_id']
    assert_equal 'Developer Demo', result['commenter']
    assert_equal 'I predict 4 model total', result['message']

    result = @ticket3.comments(@db).first
    assert_equal '3', result['ticket_id']
    assert_equal 'Quality Assurance Demo', result['commenter']
    assert_equal 'all finished', result['message']
  end

  def test_Ticket_create_history_and_get_histories
    Ticket.create_history(@db, [['prop_1', 'prev_val_1', 'curr_val_1', '4', '1']])
    Ticket.create_history(@db, [['prop_2', 'prev_val_2', 'curr_val_2', '1', '2']])
    Ticket.create_history(@db, [['prop_3', 'prev_val_3', 'curr_val_3', '2', '3']])

    result = @ticket1.histories(@db).first
    assert_equal 'prop_1', result['property']
    assert_equal 'prev_val_1', result['previous_value']
    assert_equal 'curr_val_1', result['current_value']
    assert_equal 'Quality Assurance Demo', result['name']

    result = @ticket2.histories(@db).first
    assert_equal 'prop_2', result['property']
    assert_equal 'prev_val_2', result['previous_value']
    assert_equal 'curr_val_2', result['current_value']
    assert_equal 'Admin Demo', result['name']

    result = @ticket3.histories(@db).first
    assert_equal 'prop_3', result['property']
    assert_equal 'prev_val_3', result['previous_value']
    assert_equal 'curr_val_3', result['current_value']
    assert_equal 'Project Manager Demo', result['name']
  end

  def test_Ticket_create_attachment_and_get_attachments
    Ticket.create_attachment(@db, 'obj_key_1', '3', 'Feb sales', '1')
    Ticket.create_attachment(@db, 'obj_key_2', '4', 'invoice.jpeg', '2')
    Ticket.create_attachment(@db, 'obj_key_3', '2', 'email screenshot', '3')

    result = @ticket1.attachments(@db).first
    assert_equal 'obj_key_1', result['filename']
    assert_equal 'Feb sales', result['notes']
    assert_equal 'Developer Demo', result['uploader_name']

    result = @ticket2.attachments(@db).first
    assert_equal 'obj_key_2', result['filename']
    assert_equal 'invoice.jpeg', result['notes']
    assert_equal 'Quality Assurance Demo', result['uploader_name']

    result = @ticket3.attachments(@db).first
    assert_equal 'obj_key_3', result['filename']
    assert_equal 'email screenshot', result['notes']
    assert_equal 'Project Manager Demo', result['uploader_name']
  end

  def update
    updates_hash = { 'title' => 'user authentication',
                     'priority' => 'High', 'status' => 'In Progress' }
    @ticket1.update(@db, updates_hash)

    assert_equal 'user authentication', @ticket1.title
    assert_equal 'High', @ticket1.priority
    assert_equal 'In Progress', @ticket1.status

    updates_hash = { 'title' => 'Create a login functionality',
                     'priority' => 'Low', 'status' => 'Open' }
    @ticket1.update(@db, updates_hash)
  end
end
