# require "simplecov"
# SimpleCov.start

require 'minitest/autorun'
require 'minitest/reporters'
require 'pg'

MiniTest::Reporters.use!

require_relative '../models/user'
require_relative '../models/project'

class UserTest < Minitest::Test
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

    project1 = Project.new(@db, '1')
    project1.assign_user(@db, '1', 'admin')
    project1.assign_user(@db, '2', 'project_manager')
    project1.assign_user(@db, '3', 'developer')

    project2 = Project.new(@db, '2')
    project2.assign_user(@db, '1', 'admin')
  end

  def teardown
    @db.close
  end

  def test_new
    user = User.new(@db, '3')

    assert_equal '3', user.id
    assert_equal 'Developer Demo', user.name
    assert_equal 'developer', user.role
    assert_equal 'developer@demonstration.com', user.email
    assert_equal 'dev', user.login
  end

  def test_User_register
    user = User.register(@db, 'Thomas Jefferson', 'TJIF3',
                         '3-is-bestTJ', '3-is-best@potus.gov')

    assert_equal 'Thomas Jefferson', user.name
    assert_equal 'quality_assurance', user.role
    assert_equal '3-is-best@potus.gov', user.email
    assert_equal 'TJIF3', user.login

    sql = <<~SQL
      DELETE FROM users
            WHERE name = 'Thomas Jefferson'
              AND email = '3-is-best@potus.gov';
    SQL
    @db.exec(sql)
  end

  def test_User_unique_login?
    assert_equal false, User.unique_login?(@db, 'dev')
    assert_equal true, User.unique_login?(@db, 't-jeffy')
  end

  def test_User_unique_email?
    assert_equal false, User.unique_email?(@db, 'developer@demonstration.com')
    assert_equal true, User.unique_email?(@db, 't-jeffy@potus.gov')
  end

  def test_User_user_with_login
    result = User.user_with_login(@db, 'dev')

    assert_equal result['id'], '3'
    assert_equal result['password'],
        '$2a$12$BF4oye14icNOeN1S2RQjO.ZIaTAAf.TTaVY.wbAYiJQB1NF0ufysm'

    assert_nil User.user_with_login(@db, 't-jeffy')
  end

  def test_User_name
    assert_equal 'Admin Demo', User.name(@db, '1')
  end

  def test_User_all_users
    result = User.all_users(@db).sort { |a, b| a['id'].to_i <=> b['id'].to_i }

    assert_equal '1', result[0]['id']
    assert_equal 'Admin Demo', result[0]['name']
    assert_equal 'project_manager', result[1]['role']
    assert_equal 'developer@demonstration.com', result[2]['email']
    assert_equal 'Quality Assurance Demo', result[3]['name']
  end

  def test_User_all_devs
    result = User.all_devs(@db).first

    assert_equal 'Developer Demo', result['name']
    assert_equal '3', result['id']
  end

  def test_User_assign_role
    User.assign_role(@db, 'developer', 4)
    user = User.new(@db, '4')

    assert_equal 'developer', user.role

    User.assign_role(@db, 'quality_assurance', 4)
    user = User.new(@db, '4')

    assert_equal 'quality_assurance', user.role
  end

  def test_update_info
    user = User.new(@db, '4')
    user.update_info(@db, '123_Developer', '123dev@demo.com')

    assert_equal '123_Developer', user.name
    assert_equal '123dev@demo.com', user.email

    user.update_info(@db, 'Quality Assurance Demo',
                         'quality_assurance@demonstration.com')

    assert_equal 'Quality Assurance Demo', user.name
    assert_equal 'quality_assurance@demonstration.com', user.email
  end

  def test_update_password
    user = User.new(@db, '3')
    user.update_password(@db, 'brand_new_password123!')

    sql = "SELECT password FROM user_logins WHERE id=3;"
    result = @db.exec(sql).values.first.first

    assert_equal 'brand_new_password123!', result

    hashed_pass = '$2a$12$BF4oye14icNOeN1S2RQjO.ZIaTAAf.TTaVY.wbAYiJQB1NF0ufysm'
    user.update_password(@db, hashed_pass)

    sql = "SELECT password FROM user_logins WHERE id=3;"
    result = @db.exec(sql).values.first.first

    assert_equal hashed_pass, result
  end

  def test_assigned_projects
    user = User.new(@db, '1')
    assert_equal ['1', '2'], user.assigned_projects(@db)
  end
end