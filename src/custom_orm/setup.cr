require "sqlite3"
require "mysql"
require "pg"

class CustomOrm::Setup
  @@connections = {} of Symbol => DB::Database

  # Register a new connection
  def self.register(name : Symbol, url : String)
    @@connections[name] = DB.open(url)
  end

    # Retrieve connection by name
  def self.db_connections(name : Symbol) : DB::Database
    @@connections[name]? || raise("Connection '#{name}' not registered")
  end

    # Shortcut for default
  def self.default_connection : DB::Database
    db_connections(:default)
  end
end
