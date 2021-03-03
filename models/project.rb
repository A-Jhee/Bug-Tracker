require 'pg'

class Project
  attr_reader :id, :name, :desc

  ## params
  #  -db_connection: PG::Connection object
  #  -project_id:    either string or int
  def initialize(db_connection, project_id)
    project = db_project(db_connection, project_id)

    @id = project_id
    @name = project['name']
    @desc = project['description']
  end

  ## params
  #  -db_connection:   PG::Connection object
  #  -project_name:    string
  #  -project_name:    string
  ## purpose
  #  -Creates a new project in SQL database.
  ## return object
  #  -Not used
  def self.create(db_connection, project_name, project_description)
    sql = 'INSERT INTO projects (name, description) VALUES ($1, $2);'

    db_connection.exec_params(sql, [ project_name, project_description ])
  end

  ## params
  #  -db_connection:  PG::Connection object
  #  -project_id:     string or int
  ## purpose
  #  -find and return project name using project id
  ## return object
  #  -existing project name as string
  def self.name(db_connection, project_id)
    sql = 'SELECT name FROM projects WHERE id=$1;'
    result = db_connection.exec_params(sql, [ project_id ])

    # result.values contains a username in an array contained in an array.
    # ex) [["username"]]
    result.values.first.first
  end

  ## params
  #  -db_connection:   PG::Connection object
  ## purpose
  #  -Returns all projects in the database
  ## return object
  #  -PG::Result containing all rows of 'projects' table
  def self.all(db_connection)
    sql = <<~SQL
           SELECT p.id,
                  p.name,
                  p.description,
                  count(t.id) AS ticket_count
             FROM projects AS p
        LEFT JOIN tickets AS t ON (t.project_id = p.id)
         GROUP BY p.id
         ORDER BY UPPER(p.name) ASC;
    SQL

    db_connection.exec(sql)
  end

  ## params
  #  -db_connection:  PG::Connection object
  #  -project_id:     string or int
  ## purpose
  #  -Returns a project's detail to be used in tables or project detail view
  ## return object
  #  -Hash containing a projects detail as { "column name" => "value" }
  def self.details(db_connection, project_id)
    sql = <<~SQL
           SELECT p.id,
                  p.name,
                  p.description,
                  u.name AS project_manager,
                  count(t.id) AS ticket_count
             FROM projects AS p
        LEFT JOIN projects_users_assignments AS pua
                  ON (pua.project_id = p.id AND pua.role = 'project_manager')
        LEFT JOIN users AS u ON (pua.user_id = u.id)
        LEFT JOIN tickets AS t ON (t.project_id = p.id)
            WHERE p.id = $1
         GROUP BY p.id, u.name
         ORDER BY UPPER(p.name) ASC;
    SQL

    db_connection.exec_params(sql, [ project_id ]).first
  end

  ## params
  #  -db_connection:        PG::Connection object
  #  -project_name:         string
  #  -project_description:  string
  ## purpose
  #  -update an existing project's name and description
  ## return object
  #  -not used
  def update(db_connection, project_name, project_description)
    sql = <<~SQL
      UPDATE projects
         SET name = $1,
             description = $2
       WHERE id = $3;
    SQL

    db_connection.exec_params(sql, [ project_name, project_description, id ])
  end

  ## params
  #  -db_connection:  PG::Connection object
  ## purpose
  #  -Returns all user details of users assigned to this project (self)
  ## return object
  #  -PG::Result
  def assigned_users(db_connection)
    sql = <<~SQL
          SELECT u.id,
                 u.name,
                 u.role,
                 u.email
            FROM users AS u
      RIGHT JOIN projects_users_assignments AS pua
              ON u.id = pua.user_id
           WHERE pua.project_id = $1
        ORDER BY u.name;
    SQL
    db_connection.exec_params(sql, [ id ])
  end

  ## params
  #  -db_connection:  PG::Connection object
  #  -user_id:        string or int
  #  -role:           string
  ## purpose
  #  -assigns a user, using passed in arguments, to this project
  ## return object
  #  -not used
  def assign_user(db_connection, user_id, role)
    sql = <<~SQL
      INSERT INTO projects_users_assignments (project_id, user_id, role)
           VALUES ($1, $2, $3);
    SQL
    db_connection.exec_params(sql, [ id, user_id, role ])
  end

  ## params
  #  -db_connection:  PG::Connection object
  #  -user_id:     string or int
  ## purpose
  #  -unassigns a user using user_id from project assignment table.
  ## return object
  #  -not used
  def unassign_user(db_connection, user_id)
    sql = <<~SQL
      DELETE FROM projects_users_assignments 
            WHERE project_id = $1 AND user_id = $2;
    SQL
    db_connection.exec_params(sql, [ id, user_id ])
  end

  ## params
  #  -db_connection:  PG::Connection object
  ## purpose
  #  -unassigns all user from this project
  ## return object
  #  -PG::Result
  def unassign_all(db_connection)
    sql = <<~SQL
      DELETE FROM projects_users_assignments 
            WHERE project_id = $1;
    SQL
    db_connection.exec_params(sql, [ id ])
  end

  private

  ## params
  #  -db_connection:  PG::Connection object
  #  -project_id:     string or int
  ## purpose
  #  -returns a row from projects table that matches given id
  ## return object
  #  -Hash containing a projects detail as { "column name" => "value" }
  def db_project(db_connection, project_id)
    sql = 'SELECT * FROM projects WHERE id=$1;'
    db_connection.exec_params(sql, [ project_id ]).first
  end
end
