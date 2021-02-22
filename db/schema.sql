-- SHOW hba_file;
-- change pg_hba.conf to change access permission to database

-- ------------------------------------------------------------

-- Revoke inherited permission from public schema to CREATE objects.
REVOKE CREATE
    ON SCHEMA public
  FROM PUBLIC;
-- Revoke the ability for any user to connect to "bugtracker_database".
REVOKE ALL
    ON DATABASE bugtracker_database
  FROM PUBLIC;

-- Create "bugtracker_schema" to create all objects relating to bugtracker in.
CREATE SCHEMA bugtracker_schema;
-- set search_path to include the new schema and have it be before public.
-- this syntax makes it persist at database user level (case sensitive. user
-- names with uppercase letters will require quotation marks around it).
-- ALTER ROLE "SFone" IN DATABASE bugtrack SET search_path TO bugtracker_schema,public;
-- ALTER ROLE postgres IN DATABASE bugtracker_database SET search_path TO bugtracker_schema,public;
-- This one sets it database level
ALTER DATABASE bugtracker_database SET search_path TO bugtracker_schema,public;

----------------------------------------------------------------------------
-- STATEMENTS RELATED TO USERS TABLE ---------------------------------------

CREATE TABLE users (
  id int GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  name text NOT NULL,
  role text NOT NULL DEFAULT 'Unassigned',
  email text NOT NULL
);

CREATE TABLE user_logins (
  id int GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  username text NOT NULL UNIQUE,
  password text NOT NULL,
  user_id int NOT NULL UNIQUE,
  FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
);

-- DUMMY USERS FOR DEVELOPMENT/TESTING

-- INSERT INTO users (id, name, role, email)
--   VALUES (0, 'Unassigned', 'Unassigned', 'Unassigned'),
--          (1, 'DEMO_Admin', 'admin', 'admin@demo.com'),
--          (2, 'DEMO_ProjectManager', 'project_manager', 'project_manager@demo.com'),
--          (3, 'DEMO_Developer', 'developer', 'developer@demo.com'),
--          (4, 'DEMO_QualityAssurance', 'quality_assurance', 'quality_assurance@demo.com'),
--          (5, 'TEST_Developer', 'developer', 'testdev@demo.com');

----------------------------------------------------------------------------
-- STATEMENTS RELATED TO PROJECTS TABLE ------------------------------------

CREATE TABLE projects(
  id int GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  name text NOT NULL UNIQUE,
  description text NOT NULL
);

----------------------------------------------------------------------------
-- STATEMENTS RELATED TO PROJECTS_USERS_ASSIGNMENT TABLE -------------------

CREATE TABLE projects_users_assignments(
  id int GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  project_id int NOT NULL,
  user_id int NOT NULL,
  role text NOT NULL,
  FOREIGN KEY (project_id) REFERENCES projects (id) ON DELETE CASCADE,
  FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
);

----------------------------------------------------------------------------
-- STATEMENTS RELATED TO TICKETS TABLE -------------------------------------

-- Create function that updates "updated_on" column in "tickets" table with
-- current timestamp. Function returns a trigger.
CREATE OR REPLACE FUNCTION update_timestamp()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_on = now();
  RETURN NEW;
END;
$$ language 'plpgsql';

-- Contains info about all submitted tickets.
CREATE TABLE tickets (
  id int GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  status text NOT NULL DEFAULT 'Open',
  title text NOT NULL,
  description text NOT NULL DEFAULT 'N/A',
  type text NOT NULL,
  priority text NOT NULL DEFAULT 'Low',
  submitter_id int NOT NULL,
  project_id int NOT NULL,
  developer_id int NOT NULL DEFAULT 0,
  created_on timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_on timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (submitter_id) REFERENCES users (id) ON DELETE CASCADE,
  FOREIGN KEY (project_id) REFERENCES projects (id) ON DELETE CASCADE
);

-- Create trigger that will call "update_timestamp" function when a row
-- of tickets table updates.
CREATE TRIGGER update_timestamp BEFORE 
     UPDATE ON tickets 
     FOR EACH ROW EXECUTE PROCEDURE update_timestamp();

-- Contains info about all ticket comments.
CREATE TABLE ticket_comments (
  id int GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  comment text NOT NULL,
  commenter_id int NOT NULL,
  ticket_id int NOT NULL,
  created_on timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (commenter_id) REFERENCES users (id) ON DELETE CASCADE,
  FOREIGN KEY (ticket_id) REFERENCES tickets (id) ON DELETE CASCADE
);

-- Contains info about all ticket update history.
CREATE TABLE ticket_update_history (
  id int GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  property text NOT NULL,
  previous_value text NOT NULL,
  current_value text NOT NULL,
  user_id int NOT NULL,
  ticket_id int NOT NULL,
  updated_on timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
  FOREIGN KEY (ticket_id) REFERENCES tickets (id) ON DELETE CASCADE
);

-- Contains info about all ticket attachments. "filepath" points to
-- uploaded file's location within web server filesystem.
CREATE TABLE ticket_attachments (
  id int GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  filename text NOT NULL,
  uploader_id int NOT NULL,
  notes text NOT NULL DEFAULT 'n/a',
  ticket_id int NOT NULL,
  uploaded_on timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (ticket_id) REFERENCES tickets (id) ON DELETE CASCADE,
  FOREIGN KEY (uploader_id) REFERENCES users (id) ON DELETE CASCADE
);

-- ------------------------------------------------------------

-- "auth" role will have limited privileges to:
-- SELECT, INSERT users and user_logins in order to authenticate
-- user login.

CREATE ROLE auth;

GRANT CONNECT
  ON DATABASE bugtracker_database
  TO auth;

GRANT USAGE
   ON SCHEMA bugtracker_schema
   TO auth;

GRANT SELECT, INSERT ON TABLE users, user_logins TO auth;

GRANT USAGE ON SEQUENCE users_id_seq, user_logins_id_seq TO auth;

CREATE USER authentication
       WITH PASSWORD 'ldihn1uBGYJ3ESFQly0cpZ97MXPkGdLouTcD9czo';

GRANT auth TO authentication;

-- ------------------------------------------------------------

-- "administrator" role will have full privileges to:
-- SELECT, INSERT, UPDATE, and DELETE: all tables

CREATE ROLE administrator;

GRANT CONNECT
   ON DATABASE bugtracker_database
   TO administrator;

GRANT USAGE
   ON SCHEMA bugtracker_schema
   TO administrator;

GRANT SELECT,
      INSERT,
      UPDATE,
      DELETE
          ON ALL TABLES 
          IN SCHEMA bugtracker_schema TO administrator;

GRANT USAGE ON ALL SEQUENCES IN SCHEMA bugtracker_schema TO administrator;

CREATE USER admin
       WITH PASSWORD 'dHFlohuCYtjLY7KzD2Xxf3ipjB8U4bOz9eXDf74t';

GRANT administrator TO admin;

-- ------------------------------------------------------------

-- "p_m" (project manager) role will have the privileges to:
-- SELECT, INSERT, and UPDATE: "tickets"
-- SELECT and INSERT: "ticket_comments", "ticket_attachments"
-- SELECT: "ticket_update_history", "users"
-- SELECT and UPDATE: "projects", "projects_users_assignments"

CREATE ROLE p_m;

GRANT CONNECT
   ON DATABASE bugtracker_database
   TO p_m;

GRANT USAGE
   ON SCHEMA bugtracker_schema
   TO p_m;

GRANT SELECT, INSERT, DELETE ON TABLE projects_users_assignments TO p_m;

GRANT SELECT, INSERT, UPDATE ON TABLE tickets TO p_m;

GRANT SELECT, INSERT ON TABLE ticket_comments,
                              ticket_update_history,
                              ticket_attachments TO p_m;

GRANT SELECT, UPDATE ON TABLE users,
                              user_logins,
                              projects TO p_m;

GRANT SELECT ON TABLE users TO p_m;

GRANT USAGE ON 
      SEQUENCE users_id_seq,
               projects_users_assignments_id_seq,
               tickets_id_seq,
               ticket_comments_id_seq,
               ticket_attachments_id_seq,
               projects_id_seq,
               ticket_update_history_id_seq
            TO p_m;

CREATE USER project_manager
       WITH PASSWORD 'T0qK8It4ZCsqm2nAG3Fo583jyBucGuc2tBrGdLn2';

GRANT p_m TO project_manager;

-- ------------------------------------------------------------

-- "dev" (developer) role will have the privileges to:
-- SELECT, INSERT, and UPDATE: "tickets"
-- SELECT and INSERT: "ticket_comments", "ticket_attachments"
-- SELECT: "ticket_update_history", "users"

CREATE ROLE dev;

GRANT CONNECT
   ON DATABASE bugtracker_database
   TO dev;

GRANT USAGE
   ON SCHEMA bugtracker_schema
   TO dev;

GRANT SELECT, INSERT, UPDATE ON TABLE tickets TO dev;

GRANT SELECT, INSERT ON TABLE ticket_comments,
                              ticket_update_history,
                              ticket_attachments TO dev;

GRANT SELECT, UPDATE ON TABLE users,
                              user_logins TO dev;

GRANT SELECT ON TABLE projects,
                      projects_users_assignments
                   TO dev;

GRANT USAGE ON 
      SEQUENCE users_id_seq,
               tickets_id_seq,
               ticket_comments_id_seq,
               ticket_attachments_id_seq,
               ticket_update_history_id_seq
            TO dev;

CREATE USER developer
       WITH PASSWORD 'Idttur5jnNmGFeBIYKvCm6VGjf63z4HnxKubSkEm';

GRANT dev TO developer;

-- ------------------------------------------------------------

-- "q_a" (quality assurance) role will have the privileges to:
-- SELECT, INSERT, and UPDATE: "tickets"
-- SELECT and INSERT: "ticket_comments", "ticket_attachments"
-- SELECT: "ticket_update_history", "users", "projects_users_assignments"

CREATE ROLE q_a;

GRANT CONNECT
   ON DATABASE bugtracker_database
   TO q_a;

GRANT USAGE
   ON SCHEMA bugtracker_schema
   TO q_a;

GRANT SELECT, INSERT, UPDATE ON TABLE tickets TO q_a;

GRANT SELECT, INSERT ON TABLE ticket_comments, 
                              ticket_update_history, 
                              ticket_attachments TO q_a;

GRANT SELECT, UPDATE ON TABLE users,
                              user_logins TO q_a;                             

GRANT SELECT ON TABLE projects,
                      projects_users_assignments
                   TO q_a;

GRANT USAGE ON 
      SEQUENCE users_id_seq,
               tickets_id_seq,
               ticket_comments_id_seq,
               ticket_attachments_id_seq,
               ticket_update_history_id_seq
            TO q_a;

CREATE USER quality_assurance
       WITH PASSWORD 'by4eUyAs7xA4aceqnjLjmMNZo1KqgUfQbnQMBy9J';

GRANT q_a TO quality_assurance;

-- ------------------------------------------------------------
-- STATEMENT CRAFTING TABLE ------------------------------------------------------------

        SELECT tuh.property,
               tuh.previous_value,
               tuh.current_value,
               tuh.updated_on,
               u.name
          FROM ticket_update_history AS tuh
          JOIN users AS u ON (u.id = tuh.user_id)
         WHERE ticket_id = 1
      ORDER BY updated_on DESC;
