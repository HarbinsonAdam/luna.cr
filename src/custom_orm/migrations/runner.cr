# src/custom_orm/migrations/runner.cr
require "./base_migration"
require "../exec"
require "../setup"
require "../context"  # if you added the tx connection context

module CustomOrm
  class MigrationRunner
    class_getter migrations = [] of CustomOrm::BaseMigration.class

    def initialize(@connection_name : Symbol = :default, @verbose : Bool = true); end

    # Returns true if every known migration class has a row in schema_migrations
    def all_migrations_applied? : Bool
      pending_versions.empty?
    end

    # Returns migration versions that exist in code but are not yet applied in DB
    def pending_versions : Array(String)
      db  = Setup.db_connections(@connection_name)
      dia = Setup.dialect(@connection_name)
      ensure_schema_migrations(db, dia)

      applied = migrated_versions(db, dia)

      known = self.class.migrations
        .map { |k| migration_version(k) }
        .sort

      known.reject { |v| applied.includes?(v) }
    end

    def run_migrations
      db  = Setup.db_connections(@connection_name)
      dia = Setup.dialect(@connection_name)
      ensure_schema_migrations(db, dia)

      applied = migrated_versions(db, dia)
      pending = self.class.migrations.sort_by { |k| migration_version(k) }

      pending.each do |klass|
        version = migration_version(klass)
        next if applied.includes?(version)

        puts "== #{version} #{klass.name} : migrating" if @verbose
        db.transaction do |tx|
          CustomOrm::Context.with_connection(tx.connection) do
            klass.new(@connection_name).change
            Exec.exec(db, "INSERT INTO schema_migrations (version) VALUES ($1)", [version] of DB::Any, dia)
          end
        end
        puts "== #{version} #{klass.name} : migrated" if @verbose
      rescue ex
        puts "!! Migration #{version} failed: #{ex.message}" if @verbose
        raise ex
      end
    end

    private def ensure_schema_migrations(db : DB::Database, dia : SQL::Dialect)
      Exec.exec(db, "CREATE TABLE IF NOT EXISTS schema_migrations (version TEXT PRIMARY KEY)", [] of DB::Any, dia)
    end

    private def migrated_versions(db : DB::Database, dia : SQL::Dialect) : Set(String)
      set = Set(String).new
      Exec.query_all(db, "SELECT version FROM schema_migrations", [] of DB::Any, dia) do |rs|
        while rs.move_next
          set << rs.read(String)
        end
      end
      set
    rescue
      Set(String).new
    end

    private def migration_version(klass : CustomOrm::BaseMigration.class) : String
      name = klass.name
      if m = name.match(/V(\d{8,})/)
        m[1]
      elsif m = name.match(/(\d{8,})/)
        m[1]
      else
        raise "Cannot infer migration version from #{name} (expect ...::VYYYYMMDDHHMMSS*)"
      end
    end
  end
end
