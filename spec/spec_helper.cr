require "spec"

{% if flag?(:pg_adapter) %}
  require "pg"
{% elsif flag?(:mysql_adapter) %}
  require "mysql"
{% else %}
  require "sqlite3"
{% end %}

require "../src/luna"

module SpecDb
  extend self

  SQLITE_DB_FILE = "./spec/test.db"

  def adapter : Symbol
    {% if flag?(:pg_adapter) %}
      :pg
    {% elsif flag?(:mysql_adapter) %}
      :mysql
    {% else %}
      :sqlite
    {% end %}
  end

  def dialect : Luna::SQL::Dialect
    case adapter
    when :pg
      Luna::SQL::Dialect::Pg
    when :mysql
      Luna::SQL::Dialect::Mysql
    else
      Luna::SQL::Dialect::Sqlite
    end
  end

  def default_url : String
    case adapter
    when :pg
      ENV["LUNA_TEST_DATABASE_URL"]? || "postgres://postgres:postgres@127.0.0.1:5432/luna_test"
    when :mysql
      ENV["LUNA_TEST_DATABASE_URL"]? || "mysql://root:password@127.0.0.1:3306/luna_test"
    else
      "sqlite3:#{SQLITE_DB_FILE}"
    end
  end

  def reports_url : String
    ENV["LUNA_TEST_REPORTS_DATABASE_URL"]? || default_url
  end

  def placeholder(index : Int32) : String
    adapter == :pg ? "$#{index}" : "?"
  end

  def primary_key(column : String = "id") : String
    case adapter
    when :pg
      "#{column} BIGSERIAL PRIMARY KEY"
    when :mysql
      "#{column} BIGINT PRIMARY KEY AUTO_INCREMENT"
    else
      "#{column} INTEGER PRIMARY KEY AUTOINCREMENT"
    end
  end

  def integer(column : String, null : Bool = true) : String
    sql = "#{column} BIGINT"
    sql += " NOT NULL" unless null
    sql
  end

  def text(column : String, null : Bool = true, default : String? = nil) : String
    type = adapter == :mysql && default ? "VARCHAR(255)" : "TEXT"
    sql = "#{column} #{type}"
    sql += " NOT NULL" unless null
    sql += " DEFAULT '#{default.not_nil!.gsub("'", "''")}'" if default
    sql
  end

  def boolean(column : String, null : Bool = true, default : Bool? = nil) : String
    type = adapter == :sqlite ? "INTEGER" : "BOOLEAN"
    sql = "#{column} #{type}"
    sql += " NOT NULL" unless null
    if value = default
      rendered = adapter == :sqlite ? (value ? "1" : "0") : (value ? "TRUE" : "FALSE")
      sql += " DEFAULT #{rendered}"
    end
    sql
  end

  def setup!
    cleanup_sqlite_file
    Luna::Setup.register :default, default_url
    Luna::Setup.register :reports, reports_url
  end

  def teardown!
    cleanup_sqlite_file
  end

  private def cleanup_sqlite_file
    return unless adapter == :sqlite
    File.delete(SQLITE_DB_FILE) if File.exists?(SQLITE_DB_FILE)
  end
end

Spec.before_suite do
  SpecDb.setup!
end

Spec.after_suite do
  SpecDb.teardown!
end
