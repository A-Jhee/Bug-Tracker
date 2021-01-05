require "pg"

class DatabasePersistence
  def initialize(logger)
    @db = if Sinatra::Base.production?
            PG.connect(ENV['DATABASE_URL'])
          else
            PG.connect(dbname: "bugtracker")
          end
    @logger = logger
  end

  def query(sql_statement, *params)
    @logger.info "#{sql_statement}: #{params}"
    @db.exec_params(sql_statement, params)
  end

  def all_projects
    sql = <<~SQL
      SELECT * FROM projects;
    SQL
    result = query(sql)

    result.map do |tuple|
      {id: tuple["id"].to_i, name: tuple["name"], description: tuple["description"]}
    end
  end

  def disconnect
    @db.close
  end
end