require "pg"

class DatabasePersistence
  TICKET_PRIORITY = ["Low", "High", "Critical"]
  TICKET_STATUS = ["Open", "In Progress", "Resolved", "Add. Info Required"]
  TICKET_TYPE = ["Bug/Error Report", "Feature Request", "Service Request", "Other"]
  UNUSED_PROPERTIES_FOR_UPDATE_HISTORY = ["submitter_id", "project_id", "created_on", "updated_on"]
  PROPERTY_NAME_CONVERSION = {"title"=>"Ticket Title", "description"=>"Description", 
                               "priority"=>"Ticket Priority", "status"=>"Ticket Status", 
                               "type"=>"Ticket Type", "developer_id"=>"Assigned Developer"}

  def initialize(name)
    @db = PG.connect(dbname: name)
  end

  def query(sql_statement, *params)
    # puts "#{sql_statement}: #{params}"
    @db.exec_params(sql_statement, params)
  end

  def all_developers
    sql = "SELECT * FROM users WHERE role='developer';"
    result = query(sql)

    result
  end

  def get_user_name(user_id)
    sql = "SELECT name FROM users WHERE id=$1"
    result = query(sql, user_id)
    result.values.flatten[0]
  end

  def create_project(project_name, description)
    sql = "INSERT INTO projects (name, description) VALUES ($1, $2);"
    result = query(sql, project_name, description)
  end

  def all_projects
    sql = "SELECT * FROM projects;"
    result = query(sql)
    
    result #[{"id"=>1, "name"=>bugtracker, "description"=>desc}, {2, new, desc]}]
  end

  def get_project_name(project_id)
    sql = "SELECT name FROM projects WHERE id=$1"
    result = query(sql, project_id)
    result.values.flatten[0]
  end

  def create_ticket(status, title, description, type, priority, submitter_id, project_id, developer_id)
    sql = <<~SQL
      INSERT INTO tickets (status, title, description, type, priority, submitter_id, project_id, developer_id)
        VALUES ($1, $2, $3, $4, $5, $6::int, $7::int, $8::int);
    SQL
    query(sql, status, title, description, type, priority, submitter_id, project_id, developer_id)
  end

  def get_ticket_info(id)
    sql = "SELECT * FROM tickets WHERE id=$1"
    result = query(sql, id)
    result[0]     # hash with field names as key, and field values as value
  end

  # updates = {status: 'In Progress',
  #       description: 'Create a login functionality with minimum UI',
  #          priority: 'Critical'}
  def update_ticket(updates, id)
    sql = get_update_ticket_sql_statement(updates, id)
    query(sql, *updates.values)
  end

  def delete_ticket(id)
    sql = "DELETE FROM tickets WHERE id=$1;"
    query(sql, id)
  end

  def all_tickets
    sql = <<~SQL
      SELECT tickets.id,
        tickets.title,
        projects.name AS project_name,
        users.name AS dev_name,
        tickets.priority,
        tickets.status,
        tickets.type,
        tickets.created_on
        FROM tickets
        LEFT JOIN projects ON (projects.id = tickets.project_id)
        LEFT JOIN users ON (tickets.developer_id = users.id)
        ORDER BY tickets.created_on DESC;
    SQL
    result = query(sql)

    result
  end

  def create_comment(comment, commenter_id, ticket_id)
    sql = "INSERT INTO ticket_comments (comment, commenter_id, ticket_id)
            VALUES ($1, $2, $3);"
    query(sql, comment, commenter_id, ticket_id)
  end

  def delete_comment(comment_id)
    sql = "DELETE FROM ticket_comments WHERE id = $1;"
    query(sql, comment_id)
  end

  def get_comments(ticket_id)
    sql = <<~SQL
      SELECT tc.id AS id,
             tc.ticket_id AS ticket_id,
             u.name AS commenter,
             tc.comment AS message,
             tc.created_on AS created_on
        FROM ticket_comments AS tc
        LEFT JOIN users AS u
        ON tc.commenter_id = u.id
        WHERE tc.ticket_id = $1
        ORDER BY created_on DESC;
    SQL
    result = query(sql, ticket_id)

    result
  end

  def create_ticket_history(history_arr)
    sql = <<~SQL
      INSERT INTO ticket_update_history 
               (property, previous_value, current_value, user_id, ticket_id)
        VALUES ($1, $2, $3, $4, $5);
    SQL
    history_arr.each { |history| query(sql, *history) }
  end

  def get_ticket_histories(ticket_id)
    sql = <<~SQL
      SELECT property, previous_value, current_value, updated_on
        FROM ticket_update_history
        WHERE ticket_id = $1
        ORDER BY updated_on DESC;
    SQL
    result = query(sql, ticket_id)

    result
  end

  def create_attachment(object_key, uploader_id, notes, ticket_id)
    sql = <<~SQL
      INSERT INTO ticket_attachments (filename, uploader_id, notes, ticket_id)
        VALUES ($1, $2, $3, $4);
    SQL
    query(sql, object_key, uploader_id, notes, ticket_id)
  end

  def get_ticket_attachments(ticket_id)
    sql = <<~SQL
      SELECT ta.id AS id,
             ta.filename AS filename,
             u.name AS uploader_name,
             ta.notes AS notes,
             ta.uploaded_on AS uploaded_on
        FROM ticket_attachments AS ta
        LEFT JOIN users AS u
        ON ta.uploader_id = u.id
        WHERE ta.ticket_id = $1
        ORDER BY uploaded_on ASC;
    SQL
    result = query(sql, ticket_id)

    result
  end

  def find_submitter_tickets(submitter_id)
    sql = "SELECT * FROM tickets WHERE submitter_id=$1"
    result = query(sql, submitter_id)

    result.values    
  end

  def disconnect
    @db.close
  end

  private

  # pass in ticket id and update_hash that only contains the fields
  # being updated as key-value pairs to return an appropriate
  # sql statement with bind parameters
  def get_update_ticket_sql_statement(update_hash, ticket_id)
    result = "UPDATE tickets SET "
    result << update_hash.each_with_index.map do |(field_name, _), ind|
      field_name.to_s + "=$#{ind+1}"
    end.join(", ")
    result << " WHERE id=#{ticket_id}"
  end
end