require "../setup"
require "../exec"
require "../sql"

module Luna
  # Rails-ish migration base
  abstract class BaseMigration
    getter connection_name : Symbol

    macro inherited
      Luna::MigrationRunner.migrations << {{ @type }}
    end

    def initialize(@connection_name : Symbol = :default); end

    # ---- Directional API (choose one style) ----
    # Implement either `change` (default) or `up`/`down`.
    def change
      up
    end

    def up
      raise "Define `change` or `up`/`down` in #{self.class.name}"
    end

    def down
      raise "Define `down` in #{self.class.name} if you run downwards"
    end

    # ---- SQL passthrough ----
    def execute(sql : String)
      db  = Setup.db_connections(@connection_name)
      dia = Setup.dialect(@connection_name)
      Exec.exec(db, sql, [] of DB::Any, dia)
    end

    def execute(sql : String, *params : DB::Any)
      db  = Setup.db_connections(@connection_name)
      dia = Setup.dialect(@connection_name)
      Exec.exec(db, sql, params.to_a, dia)
    end

    # ---- Table builder (Rails-like) ----
    def create_table(name : Symbol | String, id : Bool | Symbol = true, force : Bool = false, &block : Migrations::TableDefinition ->)
      table = name.to_s
      db  = Setup.db_connections(@connection_name)
      dia = Setup.dialect(@connection_name)

      if force
        Exec.exec(db, "DROP TABLE IF EXISTS #{table}", [] of DB::Any, dia)
      end

      td = Migrations::TableDefinition.new(dia)
      if id
        pk = id.is_a?(Symbol) ? id.as(Symbol).to_s : "id"
        td.primary_key(pk)
      end

      yield td
      sql = "CREATE TABLE #{table} (#{td.columns.join(", ")})"
      Exec.exec(db, sql, [] of DB::Any, dia)
    end

    def drop_table(name : Symbol | String)
      db  = Setup.db_connections(@connection_name)
      dia = Setup.dialect(@connection_name)
      Exec.exec(db, "DROP TABLE IF EXISTS #{name}", [] of DB::Any, dia)
    end

    # change_table : yields a builder that just appends ALTERs
    def change_table(name : Symbol | String, &block : Migrations::ChangeTable ->)
      db  = Setup.db_connections(@connection_name)
      dia = Setup.dialect(@connection_name)
      ct  = Migrations::ChangeTable.new(name.to_s, dia)
      yield ct
      ct.statements.each do |sql|
        Exec.exec(db, sql, [] of DB::Any, dia)
      end
    end

    # ---- Column helpers ----
    def add_column(table : Symbol | String, col : Symbol, type : Symbol, **opts)
      db  = Setup.db_connections(@connection_name)
      dia = Setup.dialect(@connection_name)
      sql = "ALTER TABLE #{table} ADD COLUMN #{Migrations::TypeSql.column_sql(col, type, dia, opts)}"
      Exec.exec(db, sql, [] of DB::Any, dia)
    end

    def remove_column(table : Symbol | String, col : Symbol)
      db  = Setup.db_connections(@connection_name)
      dia = Setup.dialect(@connection_name)
      # SQLite >= 3.35 supports RENAME COLUMN; dropping a column is trickier.
      # Many apps just rebuild the table; here we use simple syntax where supported.
      if dia == SQL::Dialect::Pg || dia == SQL::Dialect::Mysql
        Exec.exec(db, "ALTER TABLE #{table} DROP COLUMN #{col}", [] of DB::Any, dia)
      else
        raise "remove_column not supported on SQLite here; use `change_table` to rebuild"
      end
    end

    def rename_column(table : Symbol | String, from : Symbol, to : Symbol)
      db  = Setup.db_connections(@connection_name)
      dia = Setup.dialect(@connection_name)
      if dia == SQL::Dialect::Pg || dia == SQL::Dialect::Mysql
        Exec.exec(db, "ALTER TABLE #{table} RENAME COLUMN #{from} TO #{to}", [] of DB::Any, dia)
      else
        # SQLite supports since 3.25; assume available
        Exec.exec(db, "ALTER TABLE #{table} RENAME COLUMN #{from} TO #{to}", [] of DB::Any, dia)
      end
    end

    # ---- Index helpers ----
    def add_index(table : Symbol | String, cols : Symbol | Array(Symbol), unique : Bool = false, name : String? = nil)
      db  = Setup.db_connections(@connection_name)
      dia = Setup.dialect(@connection_name)
      columns = cols.is_a?(Array(Symbol)) ? cols.as(Array(Symbol)) : [cols.as(Symbol)]
      idx_name = name || "index_#{table}_on_#{columns.join("_and_")}"
      uniq = unique ? "UNIQUE " : ""
      sql = "CREATE #{uniq}INDEX #{idx_name} ON #{table} (#{columns.join(", ")})"
      Exec.exec(db, sql, [] of DB::Any, dia)
    end

    def remove_index(table : Symbol | String, name : String? = nil, columns : Array(Symbol)? = nil)
      db  = Setup.db_connections(@connection_name)
      dia = Setup.dialect(@connection_name)
      idx = name
      unless idx
        raise "remove_index requires :name or :columns" unless columns
        idx = "index_#{table}_on_#{columns.not_nil!.join("_and_")}"
      end
      sql = if dia == SQL::Dialect::Pg
        "DROP INDEX IF EXISTS #{idx}"
      else
        # SQLite/MariaDB require table-qualified drop in some cases
        "DROP INDEX IF EXISTS #{idx}"
      end
      Exec.exec(db, sql, [] of DB::Any, dia)
    end

    # ---- Table rename ----
    def rename_table(from : Symbol | String, to : Symbol | String)
      db  = Setup.db_connections(@connection_name)
      dia = Setup.dialect(@connection_name)
      Exec.exec(db, "ALTER TABLE #{from} RENAME TO #{to}", [] of DB::Any, dia)
    end
  end
end

# Column/type builders
module Luna::Migrations
  class TableDefinition
    getter columns = [] of String
    getter dialect : Luna::SQL::Dialect

    def initialize(@dialect : Luna::SQL::Dialect); end

    def primary_key(name = "id")
      case dialect
      when Luna::SQL::Dialect::Pg
        columns << "#{name} BIGSERIAL PRIMARY KEY"
      when Luna::SQL::Dialect::Mysql
        columns << "#{name} BIGINT PRIMARY KEY AUTO_INCREMENT"
      else
        columns << "#{name} INTEGER PRIMARY KEY AUTOINCREMENT"
      end
    end

    def string(name : Symbol, limit : Int32? = nil, null : Bool = true, default : DB::Any? = nil)
      type = case dialect
             when Luna::SQL::Dialect::Pg     then (limit ? "VARCHAR(#{limit})" : "VARCHAR(255)")
             when Luna::SQL::Dialect::Mysql  then (limit ? "VARCHAR(#{limit})" : "VARCHAR(255)")
             else "TEXT"
             end
      columns << TypeSql.build_col(name, type, dialect, null: null, default: default)
    end

    def text(name : Symbol, null : Bool = true, default : DB::Any? = nil)
      columns << TypeSql.build_col(name, "TEXT", dialect, null: null, default: default)
    end

    def integer(name : Symbol, null : Bool = true, default : DB::Any? = nil)
      columns << TypeSql.build_col(name, "INTEGER", dialect, null: null, default: default)
    end

    def bigint(name : Symbol, null : Bool = true, default : DB::Any? = nil)
      type = dialect == Luna::SQL::Dialect::Sqlite ? "INTEGER" : "BIGINT"
      columns << TypeSql.build_col(name, type, dialect, null: null, default: default)
    end

    def boolean(name : Symbol, null : Bool = true, default : Bool? = nil)
      type = dialect == Luna::SQL::Dialect::Sqlite ? "INTEGER" : "BOOLEAN"

      dflt = if default.nil?
        nil
      elsif dialect == Luna::SQL::Dialect::Sqlite
        default ? 1 : 0             # becomes 1 / 0, literal handles ints fine
      else
        default                      # keep as Bool; literal() already does TRUE/FALSE
      end

      columns << TypeSql.build_col(name, type, dialect, null: null, default: dflt)
    end

    def float(name : Symbol, null : Bool = true, default : DB::Any? = nil)
      columns << TypeSql.build_col(name, "DOUBLE PRECISION", dialect, null: null, default: default)
    end

    def decimal(name : Symbol, precision : Int32 = 10, scale : Int32 = 0, null : Bool = true, default : DB::Any? = nil)
      columns << TypeSql.build_col(name, "DECIMAL(#{precision},#{scale})", dialect, null: null, default: default)
    end

    def datetime(name : Symbol, null : Bool = true, default_now : Bool = false)
      type = case dialect
            when Luna::SQL::Dialect::Pg then "TIMESTAMPTZ"
            else "DATETIME"
            end

      if default_now
        # Build SQL manually so CURRENT_TIMESTAMP is raw, not quoted
        col = "#{name} #{type}"
        col += " NOT NULL" unless null
        col += " DEFAULT CURRENT_TIMESTAMP"
        columns << col
      else
        columns << TypeSql.build_col(name, type, dialect, null: null, default: nil)
      end
    end

    def timestamps(null : Bool = false)
      datetime(:created_at, null: null, default_now: true)
      datetime(:updated_at, null: null, default_now: true)
    end
  end

  # change_table builder that accumulates ALTERs
  class ChangeTable
    getter statements = [] of String

    def initialize(@table : String, @dialect : Luna::SQL::Dialect); end

    def add(column : Symbol, type : Symbol, **opts)
      statements << "ALTER TABLE #{@table} ADD COLUMN #{TypeSql.column_sql(column, type, @dialect, opts)}"
    end

    def remove(column : Symbol)
      if @dialect == Luna::SQL::Dialect::Sqlite
        raise "SQLite remove(column) not supported in-place; rebuild the table"
      end
      statements << "ALTER TABLE #{@table} DROP COLUMN #{column}"
    end

    def rename(from : Symbol, to : Symbol)
      statements << "ALTER TABLE #{@table} RENAME COLUMN #{from} TO #{to}"
    end
  end

  # Type mapping helpers
  module TypeSql
    def self.column_sql(name : Symbol, type : Symbol, dialect : Luna::SQL::Dialect, opts)
      # opts is a NamedTuple from **opts in the caller
      raw_null = opts[:null]?
      null = raw_null.nil? ? true : raw_null.as(Bool)

      build_col(
        name,
        sql_type_for(type, dialect, opts),
        dialect,
        null: null,
        default: opts[:default]?
      )
    end

    def self.sql_type_for(type : Symbol, dialect : Luna::SQL::Dialect, opts)
      case type
      when :string
        (dialect == Luna::SQL::Dialect::Sqlite) ? "TEXT" : "VARCHAR(#{(opts[:limit]? || 255)})"
      when :text      then "TEXT"
      when :integer   then "INTEGER"
      when :bigint    then (dialect == Luna::SQL::Dialect::Sqlite ? "INTEGER" : "BIGINT")
      when :boolean   then (dialect == Luna::SQL::Dialect::Sqlite ? "INTEGER" : "BOOLEAN")
      when :float     then "DOUBLE PRECISION"
      when :decimal   then "DECIMAL(#{(opts[:precision]? || 10)},#{(opts[:scale]? || 0)})"
      when :datetime  then (dialect == Luna::SQL::Dialect::Pg ? "TIMESTAMPTZ" : "DATETIME")
      when :json      then (dialect == Luna::SQL::Dialect::Pg ? "JSONB" : "TEXT")
      else raise "Unknown column type: #{type}"
      end
    end

    def self.build_col(name : Symbol, type_sql : String, dialect : Luna::SQL::Dialect, null : Bool, default : DB::Any?)
      out = "#{name} #{type_sql}"
      out += " NOT NULL" unless null
      if default != nil
        out += " DEFAULT #{literal(default, dialect)}"
      end
      out
    end

    def self.literal(val : DB::Any, dialect : Luna::SQL::Dialect) : String
      case val
      when String
        "'#{val.gsub("'", "''")}'"
      when Time
        "'#{val.to_utc.to_s("%Y-%m-%d %H:%M:%S")}'"
      when Bool
        dialect == Luna::SQL::Dialect::Sqlite ? (val ? "1" : "0") : (val ? "TRUE" : "FALSE")
      when Nil
        "NULL"
      else
        val.to_s
      end
    end
  end
end
