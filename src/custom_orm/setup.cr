require "sqlite3"
require "mysql"
require "pg"

module CustomOrm
  class Setup
    @@connections = {} of Symbol => DB::Database
    @@dialects    = {} of Symbol => CustomOrm::SQL::Dialect

    def self.register(name : Symbol, url : String)
      @@connections[name] = DB.open(url)
      @@dialects[name]    = CustomOrm::SQL.dialect_from_url(url)
    end

    def self.db_connections(name : Symbol) : DB::Database
      @@connections[name]? || raise "Connection '#{name}' not registered"
    end

    def self.default_connection : DB::Database
      db_connections(:default)
    end

    def self.dialect(name : Symbol) : CustomOrm::SQL::Dialect
      @@dialects[name]? || raise "Dialect for '#{name}' not registered"
    end
  end
end
