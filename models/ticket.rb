require 'pg'
require 'date'

require_relative 'user'
require_relative 'project'

class Ticket
  TICKET_PRIORITY = ['Low', 'High', 'Critical']

  TICKET_STATUS =
    ['Open', 'In Progress', 'Resolved', 'Add. Info Required']

  TICKET_TYPE =
    ['Bug/Error Report', 'Feature Request', 'Service Request', 'Other']

  TICKET_PROPERTY_NAME_CONVERSION =
    {
      'title'        => 'Ticket Title',
      'description'  => 'Description',
      'priority'     => 'Ticket Priority',
      'status'       => 'Ticket Status',
      'type'         => 'Ticket Type',
      'developer_name' => 'Assigned Developer'
    }

  attr_reader :id, :status, :title, :description, :type,
              :priority, :submitter_id, :submitter_name,
              :project_id, :project_name, :developer_id,
              :developer_name, :created_on, :updated_on

  ## params
  #  -db_connection:   PG::Connection object
  #  -ticket_id:       string or int
  def initialize(db_connection, ticket_id)
    ticket = db_ticket(db_connection, ticket_id)

    @id = ticket_id
    @status = ticket['status']
    @title = ticket['title']
    @description = ticket['description']
    @type = ticket['type']
    @priority = ticket['priority']

    @submitter_id = ticket['submitter_id']
    @submitter_name = User.name(db_connection, submitter_id)

    @project_id = ticket['project_id']
    @project_name = Project.name(db_connection, project_id)

    @developer_id = ticket['developer_id']
    @developer_name = User.name(db_connection, developer_id)

    @created_on = ticket['created_on']
    @updated_on = ticket['updated_on']
  end

  ## params
  #  -db_connection:   PG::Connection object
  #  -ticket_params:   an array of data required for ticket creation
  ## purpose
  #  -creates a new ticket to 'tickets' table
  ## return object
  #  -not used
  def self.create(db_connection, ticket_params)
    sql = <<~SQL
      INSERT INTO tickets (status, title, description,
                           type, priority,
                           submitter_id, project_id, developer_id)
           VALUES         ($1,     $2,    $3,
                           $4,   $5,
                           $6::int,      $7::int,    $8::int);
    SQL

    db_connection.exec_params(sql, ticket_params)
  end

  ## params
  #  -db_connection:   PG::Connection object
  ## What: Returns PG::Result object that contains only the 
  #        relevant ticket info for all tickets. Joins with 'projects'
  #        and 'users' tables to grab project name and user name.
  ## Why:  These are the information necessary for populating all tickets view.
  #        t.submitter_id is not displayed, but used to filter the view.
  ## return object
  #  -PG::Result containing all rows of 'tickets' table
  def self.all(db_connection)
    sql = <<~SQL
          SELECT t.id,
                 p.name AS project_name,
                 t.title,
                 t.status,
                 t.priority,
                 t.type,
                 u.name AS dev_name,
                 t.created_on,
                 t.submitter_id
            FROM tickets  AS t
       LEFT JOIN projects AS p ON (p.id = t.project_id)
       LEFT JOIN users    AS u ON (t.developer_id = u.id)
        ORDER BY t.created_on DESC;
    SQL

    db_connection.exec(sql)
  end

  ## params
  #  -db_connection:    PG::Connection object
  #  -project_id:       string or int
  ## purpose
  #  -Returns all tickets submitted for given project_id
  ## return object
  #  -PG::Result
  def self.all_for(db_connection, project_id)
    sql = <<~SQL
          SELECT t.id,
                 t.title,
                 p.name AS project_name,
                 u.name AS dev_name,
                 t.priority,
                 t.status,
                 t.type,
                 t.created_on,
                 t.submitter_id,
                 t.project_id
            FROM tickets  AS t
       LEFT JOIN projects AS p ON (p.id = t.project_id)
       LEFT JOIN users    AS u ON (t.developer_id = u.id)
           WHERE t.project_id = $1
        ORDER BY t.created_on DESC;
    SQL
    db_connection.exec_params(sql, [ project_id ])
  end

  ## params
  #  -db_connection:   PG::Connection object
  ## purpose
  #  -Returns all tickets submitted within the last 3 days
  ## return object
  #  -PG::Result
  def self.last_3days(db_connection)
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
    db_connection.exec_params(sql, [ dates[0], dates[1], dates[2] ])
  end

  ## params
  #  -db_connection:   PG::Connection object
  #  -project_id:      string or int
  ## purpose
  #  -Returns all tickets submitted within the last 3 days for given project
  ## return object
  #  -PG::Result
  def self.last_3days_for(db_connection, project_id)
    sql = <<~SQL
          SELECT t.id,
                 p.name AS project_name,
                 t.title,
                 t.status,
                 t.priority,
                 t.type,
                 u.name AS dev_name,
                 t.created_on,
                 t.project_id
            FROM tickets  AS t
       LEFT JOIN projects AS p ON (p.id = t.project_id)
       LEFT JOIN users    AS u ON (t.developer_id = u.id)
           WHERE (created_on::date = $1
              OR created_on::date = $2
              OR created_on::date = $3) AND (project_id = $4);
    SQL
    today = Date.today
    dates = [today, today-1, today-2].map { |date| date.iso8601 }
    db_connection.exec_params(sql, [ dates[0], dates[1], dates[2], project_id ])
  end

  ## params
  #  -db_connection:    PG::Connection object
  #  -iso_date:         string ISO 8601 date (ex. "2021-03-02")
  ## purpose
  #  -Returns all tickets for given date with status that is not 'Resolved'
  ## return object
  #  -PG::Result
  def self.open_count(db_connection, iso_date)
    sql = <<~SQL
          SELECT date(created_on), count(id)
            FROM tickets
           WHERE created_on::date = $1
             AND status <> 'Resolved'
        GROUP BY created_on;
    SQL
    db_connection.exec_params(sql, [ iso_date ])
  end

  ## params
  #  -db_connection:    PG::Connection object
  #  -iso_date:         string ISO 8601 date (ex. "2021-03-02")
  #  -project_id:       string or int
  ## purpose
  #  -Returns all tickets for given date with status that is not 'Resolved'
  #   for the given project
  ## return object
  #  -PG::Result
  def self.open_count_for(db_connection, iso_date, project_id)
    sql = <<~SQL
          SELECT date(tickets.created_on), count(tickets.id)
            FROM tickets
            JOIN projects ON projects.id = tickets.project_id
           WHERE created_on::date = $1 AND projects.id = $2
             AND status <> 'Resolved'
        GROUP BY date;
    SQL
    db_connection.exec_params(sql, [ iso_date, project_id ])
  end

  ## params
  #  -db_connection:    PG::Connection object
  #  -iso_date:         string ISO 8601 date (ex. "2021-03-02")
  ## purpose
  #  -Returns all tickets for given date with status of 'Resolved'
  ## return object
  #  -PG::Result
  def self.resolved_count(db_connection, iso_date)
    sql = <<~SQL
          SELECT date(updated_on), count(id)
            FROM tickets
           WHERE updated_on::date = $1
             AND status = 'Resolved'
        GROUP BY updated_on;
    SQL
    db_connection.exec_params(sql, [ iso_date ])
  end

  ## params
  #  -db_connection:    PG::Connection object
  #  -iso_date:         string ISO 8601 date (ex. "2021-03-02")
  #  -project_id:       string or int
  ## purpose
  #  -Returns all tickets for given date with status of 'Resolved'
  #   for the given project
  ## return object
  #  -PG::Result
  def self.resolved_count_for(db_connection, iso_date, project_id)
    sql = <<~SQL
          SELECT date(tickets.created_on), count(tickets.id)
            FROM tickets
            JOIN projects ON projects.id = tickets.project_id
           WHERE updated_on::date = $1 AND projects.id = $2
             AND status = 'Resolved'
        GROUP BY date;
    SQL
    db_connection.exec_params(sql, [ iso_date, project_id ])
  end

  ## params
  #  -db_connection:    PG::Connection object
  #  -comment:          string
  #  -commenter_id:     string or int
  #  -ticket_id:        string or int
  ## purpose
  #  -creates a comment for a ticket in "ticket_comments" table.
  ## return object
  #  -not used
  def self.create_comment(db_connection, comment, commenter_id, ticket_id)
    sql = <<~SQL
      INSERT INTO ticket_comments (comment, commenter_id, ticket_id)
           VALUES ($1, $2, $3);
    SQL

    db_connection.exec_params(sql, [ comment, commenter_id, ticket_id ])
  end

  ## params
  #  -db_connection:    PG::Connection object
  #  -history_arr:      array of ticket history data
  ## What: Inserts ticket history row into ticket_update_history table in
  #        the database. Each updating field's old and new values is one
  #        element within 'history_arr'.
  ## Why:  A single ticket update may contain several changes. Each change
  #        creates an update history. Thus, a single ticket update may require
  #        creating multiple update history.
  ## return object
  #  -not used
  def self.create_history(db_connection, history_arr)
    sql = <<~SQL
      INSERT INTO ticket_update_history
                  (property, previous_value, current_value, user_id, ticket_id)
           VALUES ($1,       $2,             $3,            $4,      $5       );
    SQL

    history_arr.each do |history|
      db_connection.exec_params(sql, history)
    end
  end

  ## params
  #  -db_connection:  PG::Connection object
  #  -obj_key:        string representing AWS S3 object key
  #  -uploader:       string or int
  #  -notes:          string
  #  -ticket:         string or int
  ## What: A ticket may have file attachments uploaded by users.
  #        Each file can have notes to go with it.
  #        File uploads are stored in AWS S3 bucket as objects. 
  #        'filename' column stores S3 object keys.
  ## return object
  #  -not used
  def self.create_attachment(db_connection, obj_key, uploader, notes, ticket)
    sql = <<~SQL
      INSERT INTO ticket_attachments (filename, uploader_id, notes, ticket_id)
           VALUES                    ($1,       $2,          $3,    $4       );
    SQL
    db_connection.exec_params(sql, [ obj_key, uploader, notes, ticket ])
  end

  ## params
  #  -db_connection:    PG::Connection object
  ## purpose
  #  -returns all comments submitted for this ticket
  ## return object
  #  -PG::Result
  def comments(db_connection)
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

    db_connection.exec_params(sql, [ id ])
  end

  ## params
  #  -db_connection:    PG::Connection object
  ## purpose
  #  -returns all ticket update histories logged for this ticket
  ## return object
  #  -PG::Result
  def histories(db_connection)
    sql = <<~SQL
        SELECT tuh.property,
               tuh.previous_value,
               tuh.current_value,
               tuh.updated_on,
               u.name
          FROM ticket_update_history AS tuh
          JOIN users AS u ON (u.id = tuh.user_id)
         WHERE ticket_id = $1
      ORDER BY updated_on DESC;
    SQL
    db_connection.exec_params(sql, [ id ])
  end

  ## params
  #  -db_connection:    PG::Connection object
  ## What: Returns PG::Result object that contains data regarding
  #        'ticket_attachment' table in the database. Actual retrieval/download
  #        of S3 objects are performed within the controller (bugtracker.rb).
  ## return object
  #  -PG::Result
  def attachments(db_connection)
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
    db_connection.exec_params(sql, [ id ])
  end

  ## params
  #  -db_connection:   PG::Connection object
  #  -updates_hash:    Hash of updating column field names and updating
  #                    values as key:value pairs and other relevant info
  #                    example:
  # updates_hash = {
  #                 status:      'In Progress',
  #                 description: 'Create a login functionality with minimum UI',
  #                 priority:    'Critical'
  #                 }
  ## purpose
  #  -updates this ticket with user submitted edits
  ## return object
  #  -not used
  def update(db_connection, updates_hash)
    # update_sql is a private DatabasePersistence method.
    sql = update_sql(updates_hash, id)
    db_connection.exec_params(sql, updates_hash.values)
  end

  private

  ## params
  #  -db_connection:    PG::Connection object
  #  -ticket_id:        string or int
  ## purpose
  #  -Returns ticket with given ticket id
  ## return object
  #  -Hash containing corresponding row from 'tickets' table
  def db_ticket(db_connection, ticket_id)
    sql = 'SELECT * FROM tickets WHERE id=$1;'
    db_connection.exec_params(sql, [ ticket_id ]).first
  end

  ## params
  #  -updates_hash:    Hash of updating column field names and updating
  #                    values as key:value pairs and other relevant info
  #                    example:
  # updates_hash = {
  #                 status:      'In Progress',
  #                 description: 'Create a login functionality with minimum UI',
  #                 priority:    'Critical'
  #                 }
  #  -ticket_id:      string or int
  # What: Returns a psql statement string, created dynamically for
  #       only the column field names provided as the update_hash keys
  # Why:  psql does not allow column names to be dynamically set, thus
  #       string interpolation operation is performed here first.
  def update_sql(update_hash, ticket_id)
    result = 'UPDATE tickets SET '

    # update_hash is a hash of updating psql column field name as key
    # and its updating value as value. Using hash's own index as incrementing
    # counter to create '$1', '$2', etc. placeholders, each field name
    # is paired with a placeholder in a psql statement string.
    result << update_hash.each_with_index.map do |(field_name, _), ind|
      field_name.to_s + "=$#{ind + 1}"
    end.join(', ')
    result << " WHERE id=#{ticket_id}"
  end
end
