# src/custom_orm/exec.cr
require "db"
require "./sql"
require "./context"

module CustomOrm::Exec
  def self.query_all(db : DB::Database, sql : String, params : Array(DB::Any),
                    dialect : CustomOrm::SQL::Dialect, &block : DB::ResultSet ->)
    sql = CustomOrm::SQL.prepare_sql(sql, dialect)
    if conn = CustomOrm::Context.current_connection
      conn.query(sql, args: params) { |rs| yield rs }
    else
      db.query(sql, args: params) { |rs| yield rs }
    end
  end

  def self.exec(db : DB::Database, sql : String, params : Array(DB::Any),
                dialect : CustomOrm::SQL::Dialect)
    sql = CustomOrm::SQL.prepare_sql(sql, dialect)
    if conn = CustomOrm::Context.current_connection
      conn.exec(sql, args: params)
    else
      db.exec(sql, args: params)
    end
  end

  def self.query_one(db : DB::Database, sql : String, params : Array(DB::Any),
                    dialect : CustomOrm::SQL::Dialect, as : T.class) : T forall T
    sql = CustomOrm::SQL.prepare_sql(sql, dialect)
    if conn = CustomOrm::Context.current_connection
      conn.query_one(sql, args: params, as: T)
    else
      db.query_one(sql, args: params, as: T)
    end
  end
end
