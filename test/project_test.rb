# require "simplecov"
# SimpleCov.start

require 'minitest/autorun'
require 'minitest/reporters'
require 'pg'

MiniTest::Reporters.use!

require_relative '../models/project'

class ProjectTest < Minitest::Test
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

    Project.create(@db, 'bugtracker', 'WebApp built on PSQL to track bug')
    Project.create(@db, 'finance manager', 'Personal finance/budget manager')
    Project.create(@db, 'text editor', 'simple text editor')

    @project = Project.new(@db, '1')
    @project.assign_user(@db, '2', 'project_manager')
  end

  def teardown
    @db.close
  end

  def test_new
    desc = 'WebApp built on PSQL to track bug'

    assert_equal '1', @project.id
    assert_equal 'bugtracker', @project.name
    assert_equal desc, @project.desc
  end

  def test_Project_create
    Project.create(@db, 'Project: GAS', 'The greatest hits of Eurobeat')
    result = @db.exec("SELECT * FROM projects WHERE name='Project: GAS';").first

    assert_equal 'Project: GAS', result['name']
    assert_equal 'The greatest hits of Eurobeat', result['description']

    @db.exec("DELETE FROM projects where name='Project: GAS';")
  end

  def test_Project_name
    assert_equal 'bugtracker', Project.name(@db, '1')
  end

  def test_Project_all
    result = Project.all(@db).map { |project| project }

    assert_equal '1', result[0]['id']
    assert_equal 'bugtracker', result[0]['name']
    assert_equal '2', result[1]['id']
    assert_equal '3', result[2]['id']
    assert_equal 'simple text editor', result[2]['description']
  end

  def test_Project_details
    result = Project.details(@db, '1')

    assert_equal '1', result['id']
    assert_equal 'bugtracker', result['name']
    assert_equal 'WebApp built on PSQL to track bug', result['description']
    assert_equal 'Project Manager Demo', result['project_manager']
  end

  def test_update
    @project.update(@db, 'bugg zapper', 'this app zapps buggs')
    project = Project.new(@db, '1')

    assert_equal 'bugg zapper', project.name
    assert_equal 'this app zapps buggs', project.desc

    project.update(@db, 'bugtracker', 'WebApp built on PSQL to track bug')
    project = Project.new(@db, '1')

    assert_equal 'bugtracker', project.name
    assert_equal 'WebApp built on PSQL to track bug', project.desc
  end

  def test_assigned_users
    result = @project.assigned_users(@db)

    assert_equal 1, result.ntuples
    assert_equal [["2", "Project Manager Demo", "project_manager",
                   "project_manager@demo.com"]],
                 result.values
  end

  def test_assign_unassign_user
    sql = "SELECT * FROM projects_users_assignments WHERE project_id='2';"
    result = @db.exec(sql).first

    assert_nil result

    project2 = Project.new(@db, '2')
    project2.assign_user(@db, '3', 'developer')
    project2.assign_user(@db, '4', 'quality_assurance')

    sql = <<~SQL
        SELECT *
          FROM projects_users_assignments
         WHERE project_id='2'
           AND user_id='4';
    SQL
    result = @db.exec(sql).first

    assert_equal '4', result['user_id']
    assert_equal 'quality_assurance', result['role']
    assert_equal '2', result['project_id']

    project2.unassign_user(@db, '4')
    result = @db.exec(sql).first

    assert_nil result

    project2.unassign_all(@db)
    sql = "SELECT * FROM projects_users_assignments WHERE project_id='2';"
    result = @db.exec(sql).first

    assert_nil result
  end
end
