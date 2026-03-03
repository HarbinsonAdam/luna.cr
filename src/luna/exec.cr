require "db"
require "./sql"
require "./context"
require "./logging"

module Luna::Exec
  def self.query_all(db : DB::Database, sql : String, params : Array(DB::Any),
                    dialect : Luna::SQL::Dialect, model_name : String? = nil, operation : String? = nil,
                    & : DB::ResultSet ->)
    sql = Luna::SQL.prepare_sql(sql, dialect)
    started_at = Time.monotonic
    begin
      if conn = Luna::Context.current_connection
        conn.query(sql, args: params) { |result_set| yield result_set }
      else
        db.query(sql, args: params) { |result_set| yield result_set }
      end
    ensure
      elapsed_ms = (Time.monotonic - started_at).total_milliseconds
      Luna::Logging.log_query(sql, params, elapsed_ms, model_name, operation)
    end
  end

  def self.exec(db : DB::Database, sql : String, params : Array(DB::Any),
                dialect : Luna::SQL::Dialect, model_name : String? = nil, operation : String? = nil)
    sql = Luna::SQL.prepare_sql(sql, dialect)
    started_at = Time.monotonic
    begin
      if conn = Luna::Context.current_connection
        conn.exec(sql, args: params)
      else
        db.exec(sql, args: params)
      end
    ensure
      elapsed_ms = (Time.monotonic - started_at).total_milliseconds
      Luna::Logging.log_query(sql, params, elapsed_ms, model_name, operation)
    end
  end

  def self.query_one(db : DB::Database, sql : String, params : Array(DB::Any),
                    dialect : Luna::SQL::Dialect, type : T.class, model_name : String? = nil,
                    operation : String? = nil) : T forall T
    sql = Luna::SQL.prepare_sql(sql, dialect)
    started_at = Time.monotonic
    begin
      if conn = Luna::Context.current_connection
        conn.query_one(sql, args: params, as: type)
      else
        db.query_one(sql, args: params, as: type)
      end
    ensure
      elapsed_ms = (Time.monotonic - started_at).total_milliseconds
      Luna::Logging.log_query(sql, params, elapsed_ms, model_name, operation)
    end
  end
end
