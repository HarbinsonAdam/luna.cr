require "db"
require "./sql"
require "./context"

module Luna::Exec
  def self.query_all(db : DB::Database, sql : String, params : Array(DB::Any),
                    dialect : Luna::SQL::Dialect, &block : DB::ResultSet ->)
    sql = Luna::SQL.prepare_sql(sql, dialect)
    if conn = Luna::Context.current_connection
      conn.query(sql, args: params) { |rs| yield rs }
    else
      db.query(sql, args: params) { |rs| yield rs }
    end
  end

  def self.exec(db : DB::Database, sql : String, params : Array(DB::Any),
                dialect : Luna::SQL::Dialect)
    sql = Luna::SQL.prepare_sql(sql, dialect)
    if conn = Luna::Context.current_connection
      conn.exec(sql, args: params)
    else
      db.exec(sql, args: params)
    end
  end

  def self.query_one(db : DB::Database, sql : String, params : Array(DB::Any),
                    dialect : Luna::SQL::Dialect, as : T.class) : T forall T
    sql = Luna::SQL.prepare_sql(sql, dialect)
    if conn = Luna::Context.current_connection
      conn.query_one(sql, args: params, as: T)
    else
      db.query_one(sql, args: params, as: T)
    end
  end
end
