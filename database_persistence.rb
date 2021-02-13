require "pg"
require "date"

class DatabasePersistence
  TICKET_PRIORITY = %w(Low High Critical)

  TICKET_STATUS =
    ["Open", "In Progress", "Resolved", "Add. Info Required"]

  TICKET_TYPE =
    ["Bug/Error Report", "Feature Request", "Service Request", "Other"]

  UNUSED_TICKET_PROPERTIES_FOR_UPDATE_HISTORY =
    %w(submitter_id project_id created_on updated_on)

  TICKET_PROPERTY_NAME_CONVERSION =
    {
      "title"        => "Ticket Title",
      "description"  => "Description",
      "priority"     => "Ticket Priority",
      "status"       => "Ticket Status",
      "type"         => "Ticket Type",
      "developer_id" => "Assigned Developer"
    }

  USER_ROLE_CONVERSION = 
    {
      "admin" => "Admin",
      "project_manager" => "Project Manager",
      "developer" => "Developer",
      "quality_assurance" => "Quality Assurance",
      "Unassigned" => "Unassigned"
    }

  # What: Create a PG connection object and stores it as instance var.
  # Why:  Use it to make all psql interactions.
  def initialize(db_name, psql_role, password)
    @db = PG.connect(dbname: db_name, user: psql_role, password: password)
  end

  # What: Returns PG::Result object after performing psql statement
  #       with any additional params to fill the placeholders in
  #       sql_statement.
  # Why:  Simplifies making PG::Connection.exec_params calls
  def query(sql_statement, *params)
    @db.exec_params(sql_statement, params)
  end

  def disconnect
    @db.close
  end

  # -------------USERS--------------------------------------------------------- #
  # -------------USERS--------------------------------------------------------- #
  # -------------USERS--------------------------------------------------------- #
  # -------------USERS--------------------------------------------------------- #
  # -------------USERS--------------------------------------------------------- #
  # -------------USERS--------------------------------------------------------- #

  def register_new_user(full_name, username, password, email)
    sql1 = "INSERT INTO users (name, role, email) VALUES ($1, 'quality_assurance', $2);"
    query(sql1, full_name, email)

    sql2 = "SELECT id FROM users WHERE name=$1 AND email=$2;"
    user_id = query(sql2, full_name, email).first["id"]

    sql3 = <<~SQL
      INSERT INTO user_logins (username, password, user_id)
           VALUES ($1, $2, $3)
    SQL
    query(sql3, username, password, user_id)
    user_id
  end

  def unique_username?(username)
    sql = "SELECT username FROM user_logins WHERE username=$1;"
    query(sql, username).first.nil?
  end

  def unique_email?(email)
    sql = "SELECT email FROM users WHERE email=$1;"
    query(sql, email).first.nil?
  end

  def correct_username?(username)
    sql = "SELECT * FROM user_logins WHERE username=$1;"
    query(sql, username).first
  end

  def user(user_id)
    sql = "SELECT * FROM users WHERE id=$1;"
    query(sql, user_id).first
  end

  # What: Returns a username as string.
  # Why:  Makes it intuitive to retrieve username from user ID.
  def get_user_name(user_id)
    sql = "SELECT name FROM users WHERE id=$1"
    result = query(sql, user_id)

    # result.values contains a username in an array contained in an array.
    # ex) [["username"]]
    result.values.first.first
  end

  def all_developers
    sql = "SELECT * FROM users WHERE role='developer';"
    query(sql)
  end

  # What: Returns PG::Result object of all user ids assigned to a project
  # Why:  Use this in conjunction with info on all users to display users
  #       who are already assigned to the project
  def all_users_on_project(project_id)
    sql = <<~SQL
        SELECT u.id, u.role
          FROM projects_users_assignments AS pua
     LEFT JOIN users AS u ON pua.user_id = u.id
         WHERE pua.project_id = $1;
    SQL
    query(sql, project_id)
  end

  def all_users
    sql = "SELECT * FROM users ORDER BY UPPER(name) ASC;"
    query(sql)
  end

  def assign_user_to_project(project_id, user_id, role)
    sql = <<~SQL
      INSERT INTO projects_users_assignments (project_id, user_id, role)
           VALUES ($1, $2, $3);
    SQL
    query(sql, project_id, user_id, role)
  end

  def unassign_user_from_project(project_id, user_id)
    sql = <<~SQL
      DELETE FROM projects_users_assignments 
            WHERE project_id = $1 AND user_id = $2;
    SQL
    query(sql, project_id, user_id)
  end

  def unassign_all_users_from_project(project_id)
    sql = <<~SQL
      DELETE FROM projects_users_assignments 
            WHERE project_id = $1;
    SQL
    query(sql, project_id)
  end

  def get_assigned_users(project_id)
    sql = <<~SQL
      SELECT users.name,
             users.role,
             users.email
        FROM users
  RIGHT JOIN projects_users_assignments AS pua
          ON users.id = pua.user_id
       WHERE pua.project_id = $1
    ORDER BY users.name;
    SQL
    query(sql, project_id)
  end

  def users_without_roles
    sql = "SELECT * FROM users WHERE role = 'Unassigned';"
    query(sql)
  end

  # -------------PROJECTS------------------------------------------------------- #
  # -------------PROJECTS------------------------------------------------------- #
  # -------------PROJECTS------------------------------------------------------- #
  # -------------PROJECTS------------------------------------------------------- #
  # -------------PROJECTS------------------------------------------------------- #
  # -------------PROJECTS------------------------------------------------------- #

  def create_project(project_name, project_description)
    sql = "INSERT INTO projects (name, description) VALUES ($1, $2);"

    query(sql, project_name, project_description)
  end

  def all_projects
    sql = "SELECT * FROM projects ORDER BY UPPER(name) ASC;"

    query(sql)
  end

  # What: returns just the project id of the given project name
  def get_project_id(project_name)
    sql = "SELECT id FROM projects WHERE name=$1"
    result = query(sql, project_name)

    # result.values contains a project id in an array contained in an array as a string.
    # ex) [["3"]].first.first -> "3"
    result.values.first.first
  end

  # What: returns just the project name of the given project id
  def get_project_name(project_id)
    sql = "SELECT name FROM projects WHERE id=$1"
    result = query(sql, project_id)

    # result.values contains a project name in an array contained in an array.
    # ex) [["project name"]].first.first -> "project name"
    result.values.first.first
  end

  # What: returns PG::Result object containing all info of a project.
  def get_project(project_id)
    sql = "SELECT * FROM projects WHERE id=$1"
    result = query(sql, project_id)

    result.first
  end

  def update_project(project_name, project_description, project_id)
    sql_1 = "UPDATE projects SET name = $1 WHERE id = $2"
    sql_2 = "UPDATE projects SET description = $1 WHERE id = $2"
    query(sql_1, project_name, project_id)
    query(sql_2, project_description, project_id)
  end

  # -------------TICKETS-------------------------------------------------------- #
  # -------------TICKETS-------------------------------------------------------- #
  # -------------TICKETS-------------------------------------------------------- #
  # -------------TICKETS-------------------------------------------------------- #
  # -------------TICKETS-------------------------------------------------------- #
  # -------------TICKETS-------------------------------------------------------- #

  def create_ticket(status, title, description, type, priority, submitter_id, project_id, developer_id)
    sql = <<~SQL
      INSERT INTO tickets (status, title, description, type, priority, submitter_id, project_id, developer_id)
           VALUES         ($1,     $2,    $3,          $4,   $5,       $6::int,      $7::int,    $8::int);
    SQL

    query(sql, status, title, description, type, priority, submitter_id, project_id, developer_id)
  end

  def get_ticket(ticket_id)
    sql = "SELECT * FROM tickets WHERE id=$1"
    result = query(sql, ticket_id)

    result.first
  end

  # What: Returns PG::Result object that contains only the 
  #       relevant ticket info for all tickets. Joins with 'projects'
  #       and 'users' tables to grab project name and user name.
  # Why:  These are the information necessary for populating all tickets view.
  #       t.submitter_id is not displayed, but used to filter the view.
  def all_tickets
    sql = <<~SQL
          SELECT t.id,
                 t.title,
                 p.name AS project_name,
                 u.name AS dev_name,
                 t.priority,
                 t.status,
                 t.type,
                 t.created_on,
                 t.submitter_id
            FROM tickets  AS t
       LEFT JOIN projects AS p ON (p.id = t.project_id)
       LEFT JOIN users    AS u ON (t.developer_id = u.id)
        ORDER BY t.created_on DESC;
    SQL

    query(sql)
  end

  def all_tickets_for_current_user(user)
  end

  def last_3days_tickets_for_current_user(user)
    if user == "admin"
      sql = <<~SQL
            SELECT t.id,
                   p.name AS project_name,
                   t.title,
                   t.status,
                   t.priority,
                   t.type,
                   u.name AS dev_name,
                   t.created_on
              FROM tickets  AS t
         LEFT JOIN projects AS p ON (p.id = t.project_id)
         LEFT JOIN users    AS u ON (t.developer_id = u.id)
             WHERE created_on::date = $1
                OR created_on::date = $2
                OR created_on::date = $3;
      SQL
      today = Date.today
      dates = [today, today-1, today-2].map { |date| date.iso8601 }
      query(sql, dates[0], dates[1], dates[2])
    # else
    #   get all projects the user is assigned to
    #   get all tickets from only certain projects
    #   select tickets that are opened within last 3 days
    end
  end

  # Returns tickets for a specified project
  def tickets_for_project(project_id)
    sql = <<~SQL
      SELECT * FROM tickets WHERE project_id = $1 ORDER BY created_on DESC;
    SQL
    query(sql, project_id)
  end

  # What: Given a hash of updating column field names and updating values as
  #       key:value pairs and ticket id, update psql database
  # 
  # example of an updates_hash
  # updates_hash = {
  #                  status:      'In Progress',
  #                  description: 'Create a login functionality with minimum UI',
  #                  priority:    'Critical'
  #                }
  def update_ticket(updates_hash, ticket_id)
    # get_update_ticket_sql_statement is a private DatabasePersistence method.
    sql = get_update_ticket_sql_statement(updates_hash, ticket_id)

    query(sql, *updates_hash.values)
  end

  # Note: This is a permanent action. Cannot be undone.
  def delete_ticket(id)
    sql = "DELETE FROM tickets WHERE id=$1;"

    query(sql, id)
  end

  # What: Creates a comment for a ticket.
  def create_comment(comment, commenter_id, ticket_id)
    sql = "INSERT INTO ticket_comments (comment, commenter_id, ticket_id)
            VALUES ($1, $2, $3);"

    query(sql, comment, commenter_id, ticket_id)
  end

  def get_comments(ticket_id)
    sql = <<~SQL
          SELECT tc.id           AS id,
                 tc.ticket_id    AS ticket_id,
                 u.name          AS commenter,
                 tc.comment      AS message,
                 tc.created_on   AS created_on
            FROM ticket_comments AS tc
       LEFT JOIN users           AS u
              ON tc.commenter_id = u.id
           WHERE tc.ticket_id = $1
        ORDER BY created_on DESC;
    SQL

    query(sql, ticket_id)
  end

  # Note: This is a permanent action. Cannot be undone.
  def delete_comment(comment_id)
    sql = "DELETE FROM ticket_comments WHERE id = $1;"

    query(sql, comment_id)
  end

  # What: Inserts ticket history row into ticket_update_history table in
  #       the database. Each updating field's old and new values is one
  #       element within 'history_arr'.
  # Why:  A single ticket update may contain several changes. Each change
  #       creates an update history. Thus, a single ticket update may require
  #       creating multiple update history.
  def create_ticket_history(history_arr)
    sql = <<~SQL
      INSERT INTO ticket_update_history
                  (property, previous_value, current_value, user_id, ticket_id)
           VALUES ($1,       $2,             $3,            $4,      $5);
    SQL

    history_arr.each do |history|
      query(sql, *history)
    end
  end

  def get_ticket_histories(ticket_id)
    sql = <<~SQL
        SELECT property, previous_value, current_value, updated_on, user_id
          FROM ticket_update_history
         WHERE ticket_id = $1
      ORDER BY updated_on DESC;
    SQL
    query(sql, ticket_id)
  end

  # What: A ticket may have file attachments uploaded by users.
  #       Each file can have notes to go with it.
  #       File uploads are stored in AWS S3 bucket as objects. 
  #       'filename' column stores S3 object keys.
  def create_attachment(object_key, uploader_id, notes, ticket_id)
    sql = <<~SQL
      INSERT INTO ticket_attachments (filename, uploader_id, notes, ticket_id)
        VALUES ($1, $2, $3, $4);
    SQL
    query(sql, object_key, uploader_id, notes, ticket_id)
  end

  # What: Returns PG::Result object that contains data regarding
  # 'ticket_attachment' table in the database. Actual retrieval/download
  # of S3 objects are performed within the controller (bugtracker.rb).
  def get_ticket_attachments(ticket_id)
    sql = <<~SQL
          SELECT ta.id              AS id,
                 ta.filename        AS filename,
                 u.name             AS uploader_name,
                 ta.notes           AS notes,
                 ta.uploaded_on     AS uploaded_on
            FROM ticket_attachments AS ta
       LEFT JOIN users              AS u
              ON ta.uploader_id = u.id
           WHERE ta.ticket_id = $1
        ORDER BY uploaded_on ASC;
    SQL
    query(sql, ticket_id)
  end

  def get_open_ticket_count(iso_date)
    sql = <<~SQL
          SELECT date(created_on), count(id)
            FROM tickets
           WHERE created_on::date = $1
             AND status = 'Open'
        GROUP BY created_on;
    SQL
    query(sql, iso_date)
  end

  def get_resolved_ticket_count(iso_date)
    sql = <<~SQL
          SELECT date(updated_on), count(id)
            FROM tickets
           WHERE updated_on::date = $1
             AND status = 'Resolved'
        GROUP BY updated_on;
    SQL
    query(sql, iso_date)
  end

  # ---------------------------------------------------------------------------- #
  # -------------PRIVATE-------------------------------------------------------- #
  # ---------------------------------------------------------------------------- #
  
  private

  # What: Returns a psql statement string, created dynamically for
  #       only the column field names provided as the update_hash keys
  # Why:  psql does not allow column names to be dynamically set, thus
  #       string interpolation operation is performed here first.
  def get_update_ticket_sql_statement(update_hash, ticket_id)
    result = "UPDATE tickets SET "

    # update_hash is a hash of updating psql column field name as key
    # and its updating value as value. Using hash's own index as incrementing
    # counter to create '$1', '$2', etc. placeholders, each field name
    # is paired with a placeholder in a psql statement string.
    result << update_hash.each_with_index.map do |(field_name, _), ind|
      field_name.to_s + "=$#{ind + 1}"
    end.join(", ")
    result << " WHERE id=#{ticket_id}"
  end
end
