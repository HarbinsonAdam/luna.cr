require "sqlite3"
require "mysql"
require "pg"
require "./logging"

module Luna
  class Setup
    @@connections = {} of Symbol => DB::Database
    @@dialects    = {} of Symbol => Luna::SQL::Dialect

    def self.register(name : Symbol, url : String)
      @@connections[name] = DB.open(url)
      @@dialects[name]    = Luna::SQL.dialect_from_url(url)
    end

    def self.db_connections(name : Symbol) : DB::Database
      @@connections[name]? || raise "Connection '#{name}' not registered"
    end

    def self.default_connection : DB::Database
      db_connections(:default)
    end

    def self.dialect(name : Symbol) : Luna::SQL::Dialect
      @@dialects[name]? || raise "Dialect for '#{name}' not registered"
    end

    def self.enable_query_logging
      Luna::Logging.enable_query_logging
    end

    def self.disable_query_logging
      Luna::Logging.disable_query_logging
    end

    def self.query_logging_enabled? : Bool
      Luna::Logging.query_logging_enabled?
    end
  end
end
