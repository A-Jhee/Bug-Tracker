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

  ## params
  #  -db_connection:   PG::Connection object
  #  -user_id:         string or int
  def initialize(db_connection, user_id)
    user = db_user(db_connection, user_id)

    @id = user_id
    @name = user['name']
    @role = user['role']
    @email = user['email']
    @login = db_login(db_connection)
  end

  ## params
  #  -db_connection:   PG::Connection object
  #  -full_name:       string
  #  -login:           string
  #  -password:        string
  #  -email:           string
  ## purpose
  #  -creates a new user in 'users' table and 'user_logins' table
  ## return object
  #  -User class instance of the newly registered user
  def self.register(db_connection, full_name, login, password, email)
    create_new_user(db_connection, full_name, email)

    user_id = user_id(db_connection, full_name, email)
    create_new_login(db_connection, login, password, user_id)
    User.new(db_connection, user_id)
  end

  ## params
  #  -db_connection:  PG::Connection object
  #  -login:          string
  ## purpose
  #  -returns boolean value based on whether given login name already
  #   exists in 'user_logins' table or not
  ## return object
  #  -true or false
  def self.unique_login?(db_connection, login)
    sql = 'SELECT username FROM user_logins WHERE username=$1;'
    db_connection.exec_params(sql, [ login ]).first.nil?
  end

  ## params
  #  -db_connection:  PG::Connection object
  #  -email:          string
  ## purpose
  #  -returns boolean value based on whether given email already
  #   exists in 'user_logins' table or not
  ## return object
  #  -true or false
  def self.unique_email?(db_connection, email)
    sql = 'SELECT email FROM users WHERE email=$1;'
    db_connection.exec_params(sql, [ email ]).first.nil?
  end

  ## params
  #  -db_connection:  PG::Connection object
  #  -login:          string
  ## purpose
  #  -Returns user id and hashed password associated with the given login name
  ## return object
  #  -Hash containing user_id & hashed_password
  def self.user_with_login(db_connection, login)
    sql = <<~SQL
      SELECT u.id, ul.password
        FROM users AS u
        JOIN user_logins AS ul ON ul.user_id = u.id
       WHERE username=$1;
    SQL
    db_connection.exec_params(sql, [ login ]).first
  end

  ## params
  #  -db_connection:   PG::Connection object
  #  -user_id:         string or int
  ## purpose
  #  -returns user name associated with given user_id
  ## return object
  #  -user name as string
  def self.name(db_connection, user_id)
    sql = 'SELECT name FROM users WHERE id=$1;'
    result = db_connection.exec_params(sql, [ user_id ])

    # result.values contains a username in an array contained in an array.
    # ex) [['username']]
    result.values.first.first
  end

  ## params
  #  -db_connection:    PG::Connection object
  ## purpose
  #  -returns all users in the database
  ## return object
  #  -PG::Result
  def self.all_users(db_connection)
    sql = 'SELECT * FROM users WHERE id > 0 ORDER BY UPPER(name) ASC;'
    db_connection.exec(sql)
  end

  ## params
  #  -db_connection:    PG::Connection object
  ## purpose
  #  -returns all users with 'developer' role in the database
  ## return object
  #  -PG::Result
  def self.all_devs(db_connection)
    sql = "SELECT * FROM users WHERE role='developer' ORDER BY UPPER(name) ASC;"
    db_connection.exec(sql)
  end

  ## params
  #  -db_connection:    PG::Connection object
  ## purpose
  #  -returns all emails in the database
  ## return object
  #  -PG::Result
  def self.all_emails(db_connection)
    sql = 'SELECT email FROM users WHERE id > 0;'
    db_connection.exec(sql).values.flatten
  end

  ## params
  #  -db_connection:   PG::Connection object
  #  -role:            string
  #  -user_id:         string or int
  ## purpose
  #  -assigns given role for the given user_id
  ## return object
  #  -not used
  def self.assign_role(db_connection, role, user_id)
    sql = 'UPDATE users SET role=$1 WHERE id=$2;'
    db_connection.exec_params(sql, [ role, user_id ])
  end

  ## params
  #  -db_connection:    PG::Connection object
  #  -full_name:        string
  #  -email:            string
  ## purpose
  #  -updates this user's name and e-mail. also updates instance variables
  ## return object
  #  -not used
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

  ## params
  #  -db_connection:    PG::Connection object
  ## purpose
  #  -returns this user's hashed_password
  ## return object
  #  -string containing hashed_password
  def password(db_connection)
    sql = 'SELECT password FROM user_logins WHERE user_id=$1;'
    db_connection.exec_params(sql, [ id ]).first['password']
  end

  ## params
  #  -db_connection:   PG::Connection object
  #  -new_pass:        string hashed with BCrypt
  ## purpose
  #  -updates this user's hashed_password
  ## return object
  #  -not used
  def update_password(db_connection, new_pass)
    sql = 'UPDATE user_logins SET password=$1 WHERE id=$2;'
    db_connection.exec_params(sql, [ new_pass, id ])
  end

  ## params
  #  -db_connection:    PG::Connection object
  ## purpose
  #  -returns all projects this user is assigned to
  ## return object
  #  -array of String numbers (ex. ['2', '3', '5', '9'])
  def assigned_projects(db_connection)
    sql = <<~SQL
        SELECT project_id
          FROM projects_users_assignments
         WHERE user_id = $1
      ORDER BY project_id;
    SQL
    db_connection.exec_params(sql, [ id ]).values.flatten
  end

# ----------------------------------------------------------------------------
# ------PRIVATE------------PRIVATE------------PRIVATE------------PRIVATE------
# ------PRIVATE------------PRIVATE------------PRIVATE------------PRIVATE------
# ----------------------------------------------------------------------------

  private

  ## params
  #  -db_connection:  PG::Connection object
  #  -login:          string
  #  -password:       string
  #  -user_id:        string or int
  ## purpose
  #  -creates a new user in 'user_logins' table
  ## return object
  #  -not used
  def self.create_new_login(db_connection, login, password, user_id)
    sql = <<~SQL
      INSERT INTO user_logins (username, password, user_id)
           VALUES ($1, $2, $3);
    SQL
    db_connection.exec_params(sql, [ login, password, user_id ])
  end

  ## params
  #  -db_connection:  PG::Connection object
  #  -full_name:      string
  #  -email:          string
  ## purpose
  #  -creates a new user in 'users' table
  ## return object
  #  -not used
  def self.create_new_user(db_connection, full_name, email)
    sql = "INSERT INTO users (name, role, email) VALUES ($1, 'quality_assurance', $2);"
    db_connection.exec_params(sql, [ full_name, email ])
  end

  ## params
  #  -db_connection:  PG::Connection object
  #  -full_name:      string
  #  -email:          string
  ## purpose
  #  -returns user id given user's name and e-mail
  ## return object
  #  -int as string (ex. "23")
  def self.user_id(db_connection, full_name, email)
    sql = 'SELECT id FROM users WHERE name=$1 AND email=$2;'
    db_connection.exec_params(sql, [ full_name, email ]).first['id']
  end

  ## params
  #  -db_connection:   PG::Connection object
  #  -user_id:         string or int
  ## purpose
  #  -returns user from 'users' table for given user_id
  ## return object
  #  -Hash containing data for a row of 'users' table
  def db_user(db_connection, user_id)
    sql = 'SELECT * FROM users WHERE id=$1;'
    db_connection.exec_params(sql, [ user_id ]).first
  end

  ## params
  #  -db_connection:   PG::Connection object
  ## purpose
  #  -returns login name from 'user_logins' table for this user
  ## return object
  #  -login name as string
  def db_login(db_connection)
    sql = 'SELECT username FROM user_logins WHERE user_id=$1'
    result = db_connection.exec_params(sql, [ id ])
    result.values.first.first
  end
end
