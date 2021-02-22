require 'pg'

class User
  USER_ROLE_CONVERSION = 
    {
      'admin' => 'Admin',
      'project_manager' => 'Project Manager',
      'developer' => 'Developer',
      'quality_assurance' => 'Quality Assurance',
      'Unassigned' => 'Unassigned'
    }

  attr_reader :id, :name, :role, :email, :login

  def initialize(db_connection, user_id)
    user = db_user(db_connection, user_id)

    @id = user_id
    @name = user['name']
    @role = user['role']
    @email = user['email']
    @login = db_login(db_connection)
  end

  def self.register(db_connection, full_name, login, password, email)
    create_new_user(db_connection, full_name, email)

    user_id = user_id(db_connection, full_name, email)
    create_new_login(db_connection, login, password, user_id)
    User.new(db_connection, user_id)
  end

  def self.unique_login?(db_connection, login)
    sql = 'SELECT username FROM user_logins WHERE username=$1;'
    db_connection.exec_params(sql, [ login ]).first.nil?
  end

  def self.unique_email?(db_connection, email)
    sql = 'SELECT email FROM users WHERE email=$1;'
    db_connection.exec_params(sql, [ email ]).first.nil?
  end

  def self.user_with_login(db_connection, login)
    sql = <<~SQL
      SELECT u.id, ul.password
        FROM users AS u
        JOIN user_logins AS ul ON ul.user_id = u.id
       WHERE username=$1;
    SQL
    db_connection.exec_params(sql, [ login ]).first
  end

  def self.name(db_connection, user_id)
    sql = 'SELECT name FROM users WHERE id=$1;'
    result = db_connection.exec_params(sql, [ user_id ])

    # result.values contains a username in an array contained in an array.
    # ex) [['username']]
    result.values.first.first
  end

  def self.all_users(db_connection)
    sql = 'SELECT * FROM users WHERE id > 0 ORDER BY UPPER(name) ASC;'
    db_connection.exec(sql)
  end

  def self.all_devs(db_connection)
    sql = "SELECT * FROM users WHERE role='developer' ORDER BY UPPER(name) ASC;"
    db_connection.exec(sql)
  end

  def self.all_emails(db_connection)
    sql = 'SELECT email FROM users WHERE id > 0;'
    db_connection.exec(sql).values.flatten
  end

  def self.assign_role(db_connection, role, user_id)
    sql = 'UPDATE users SET role=$1 WHERE id=$2;'
    db_connection.exec_params(sql, [ role, user_id ])
  end

  def update_info(db_connection, full_name, email)
    sql = <<~SQL
      UPDATE users
         SET name = $1,
             email = $2
       WHERE id = $3;
    SQL
    db_connection.exec_params(sql, [ full_name, email, id ])
    @name = full_name
    @email = email
  end

  def password(db_connection)
    sql = 'SELECT password FROM user_logins WHERE user_id=$1;'
    db_connection.exec_params(sql, [ id ]).first['password']
  end

  def update_password(db_connection, new_pass)
    sql = 'UPDATE user_logins SET password=$1 WHERE id=$2;'
    db_connection.exec_params(sql, [ new_pass, id ])
  end

  def assigned_projects(db_connection)
    sql = <<~SQL
        SELECT project_id
          FROM projects_users_assignments
         WHERE user_id = $1
      ORDER BY project_id;
    SQL
    db_connection.exec_params(sql, [ id ]).values.flatten
  end

  private

  def self.create_new_login(db_connection, login, password, user_id)
    sql = <<~SQL
      INSERT INTO user_logins (username, password, user_id)
           VALUES ($1, $2, $3);
    SQL
    db_connection.exec_params(sql, [ login, password, user_id ])
  end

  def self.create_new_user(db_connection, full_name, email)
    sql = "INSERT INTO users (name, role, email) VALUES ($1, 'quality_assurance', $2);"
    db_connection.exec_params(sql, [ full_name, email ])
  end

  def self.user_id(db_connection, full_name, email)
    sql = 'SELECT id FROM users WHERE name=$1 AND email=$2;'
    db_connection.exec_params(sql, [ full_name, email ]).first['id']
  end

  def db_user(db_connection, user_id)
    sql = 'SELECT * FROM users WHERE id=$1;'
    db_connection.exec_params(sql, [ user_id ]).first
  end

  def db_login(db_connection)
    sql = 'SELECT username FROM user_logins WHERE user_id=$1'
    result = db_connection.exec_params(sql, [ id ])
    result.values.first.first
  end
end
