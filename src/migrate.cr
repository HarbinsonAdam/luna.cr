abstract class CustomOrm::BaseMigration; end

class CustomOrm::MigrationRunner
  class_getter migrations = [] of CustomOrm::BaseMigration.class

  def initialize; end

  def run_migrations
    res = CouchbaseGetBucketClient.new(Couchbase.settings.bucket_name).perform

    if res.status == HTTP::Status::NOT_FOUND
      puts "Bucket not found, creating a new one"
      CouchbaseCreateBucketClient.new(CouchbaseBucketParameters.new(Couchbase.settings.bucket_name, 256)).perform
      sleep(5)
    end

    scopes_res = CouchbaseGetScopesClient.new(Couchbase.settings.bucket_name).perform
    bucket_scope = scopes_res.scopes.find { |scope| scope.name == Couchbase.settings.scope_name }

    if !bucket_scope
      puts "Scope not found, creating a new one"
      CouchbaseCreateScopeClient.new(CouchbaseScopeParameters.new(Couchbase.settings.scope_name)).perform
      sleep(1)
    end

    if !bucket_scope || !bucket_scope.collections.find { |collection| collection.name == "migrations" }
      puts "No Migrations Collection found, creating a new one"
      CouchbaseCreateCollectionClient.new(CouchbaseCollectionParameters.new("migrations")).perform
      sleep(1)
    end

    migrations = Migration.all

    self.class.migrations.each do |klass|
      begin
        migration_id = klass.to_s.split("::V").last.to_u64

        if migrations.find { |migration| migration.version === migration_id }
          next
        end

        klass.new.change
        Migration.new(version: migration_id).save
        sleep(1)
      rescue ex
        puts "#{ex.message} - Failed migration: #{migration_id}"
        break
      end
    end
  end
end
