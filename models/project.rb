require 'pg'

class Project
  attr_reader :id, :name, :desc

  def initialize(db_connection, project_id)
    project = db_project(db_connection, project_id)

    @id = project_id
    @name = project['name']
    @desc = project['description']
  end

  def self.create(db_connection, project_name, project_description)
    sql = 'INSERT INTO projects (name, description) VALUES ($1, $2);'

    db_connection.exec_params(sql, [ project_name, project_description ])
  end

  def self.name(db_connection, project_id)
    sql = 'SELECT name FROM projects WHERE id=$1;'
    result = db_connection.exec_params(sql, [ project_id ])

    # result.values contains a username in an array contained in an array.
    # ex) [["username"]]
    result.values.first.first
  end

  def self.all(db_connection)
    sql = <<~SQL
           SELECT p.id,
                  p.name,
                  p.description,
                  u.name AS project_manager,
                  count(t.id) AS ticket_count
             FROM projects AS p
        LEFT JOIN projects_users_assignments AS pua ON (pua.project_id = p.id AND pua.role = 'project_manager')
        LEFT JOIN users AS u ON (pua.user_id = u.id)
        LEFT JOIN tickets AS t ON (t.project_id = p.id)
         GROUP BY p.id, u.name
         ORDER BY UPPER(p.name) ASC;
    SQL

    db_connection.exec(sql)
  end

  def self.details(db_connection, project_id)
    sql = <<~SQL
           SELECT p.id,
                  p.name,
                  p.description,
                  u.name AS project_manager,
                  count(t.id) AS ticket_count
             FROM projects AS p
        LEFT JOIN projects_users_assignments AS pua ON (pua.project_id = p.id AND pua.role = 'project_manager')
        LEFT JOIN users AS u ON (pua.user_id = u.id)
        LEFT JOIN tickets AS t ON (t.project_id = p.id)
            WHERE p.id = $1
         GROUP BY p.id, u.name
         ORDER BY UPPER(p.name) ASC;
    SQL

    db_connection.exec_params(sql, [ project_id ]).first
  end

  def update(db_connection, project_name, project_description)
    sql = <<~SQL
      UPDATE projects
         SET name = $1,
             description = $2
       WHERE id = $3;
    SQL

    db_connection.exec_params(sql, [ project_name, project_description, id ])
  end

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

  def assign_user(db_connection, user_id, role)
    sql = <<~SQL
      INSERT INTO projects_users_assignments (project_id, user_id, role)
           VALUES ($1, $2, $3);
    SQL
    db_connection.exec_params(sql, [ id, user_id, role ])
  end

  def unassign_user(db_connection, user_id)
    sql = <<~SQL
      DELETE FROM projects_users_assignments 
            WHERE project_id = $1 AND user_id = $2;
    SQL
    db_connection.exec_params(sql, [ id, user_id ])
  end

  def unassign_all(db_connection)
    sql = <<~SQL
      DELETE FROM projects_users_assignments 
            WHERE project_id = $1;
    SQL
    db_connection.exec_params(sql, [ id ])
  end

  private

  def db_project(db_connection, project_id)
    sql = 'SELECT * FROM projects WHERE id=$1;'
    db_connection.exec_params(sql, [ project_id ]).first
  end
end
