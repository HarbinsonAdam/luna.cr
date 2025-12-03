require "uri"

module CustomOrm
  module SQL
    enum Dialect
      Pg
      Sqlite
      Mysql
    end

    def self.dialect_from_url(url : String) : Dialect
      uri = URI.parse(url)
      scheme = (uri.scheme || "").downcase
      case scheme
      when "postgres", "postgresql", "pg" then Dialect::Pg
      when "sqlite", "sqlite3"            then Dialect::Sqlite
      when "mysql", "mysql2"              then Dialect::Mysql
      else                                     Dialect::Sqlite  # safe default for tests
      end
    end

    # Rewrite $1,$2,... into the target dialect’s placeholders.
    def self.prepare_sql(sql : String, dialect : Dialect) : String
      case dialect
      when Dialect::Pg
        sql
      when Dialect::Sqlite
        # use the match object to avoid any nilable globals
        sql.gsub(/\$(\d+)/) { |m| "?#{m[1]}" }
      when Dialect::Mysql
        sql.gsub(/\$(\d+)/, "?")
      else
        sql
      end
    end

    def self.sqlite_supports_returning?(db : DB::Database) : Bool
      version = db.query_one("select sqlite_version()", as: String)
      version >= "3.35"
    rescue
      false
    end
  end
end
