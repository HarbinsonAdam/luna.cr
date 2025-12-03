require "spec"

# Dummy migrations to exercise the registration macro and version parser
module CustomOrm::Migrations::TestMigrations
  # Example: classic timestamp-based migration name
  class V20250101010101_CreateUsers < CustomOrm::BaseMigration
    def change
      # no-op for this unit test
    end
  end

  # Example: name that only contains a long digit sequence
  class CreatePosts20250102020202 < CustomOrm::BaseMigration
    def change
      # no-op for this unit test
    end
  end

  # Example: missing version in the class name to trigger an error
  class CreateComments < CustomOrm::BaseMigration
    def change
      # no-op
    end
  end
end

# Test helper to access the private #migration_version for specs
class TestMigrationRunner < CustomOrm::MigrationRunner
  def version_for(klass : CustomOrm::BaseMigration.class) : String
    # This can call the private method because it's inside the subclass
    migration_version(klass)
  end
end

describe CustomOrm::MigrationRunner do
  it "registers migrations via register_on_inherit macro" do
    migrations = CustomOrm::MigrationRunner.migrations

    migrations.any?(&.name.ends_with?("V20250101010101_CreateUsers")).should be_true
    migrations.any?(&.name.ends_with?("CreatePosts20250102020202")).should be_true
  end

  describe "#migration_version" do
    it "extracts version from names like VYYYYMMDDHHMMSS" do
      klass = CustomOrm::Migrations::TestMigrations::V20250101010101_CreateUsers
      runner = TestMigrationRunner.new

      version = runner.version_for(klass)
      version.should eq("20250101010101")
    end

    it "extracts version from any long digit sequence in the name" do
      klass = CustomOrm::Migrations::TestMigrations::CreatePosts20250102020202
      runner = TestMigrationRunner.new

      version = runner.version_for(klass)
      version.should eq("20250102020202")
    end

    it "raises when no version is inferable" do
      klass = CustomOrm::Migrations::TestMigrations::CreateComments
      runner = TestMigrationRunner.new

      expect_raises(Exception, /Cannot infer migration version/) do
        runner.version_for(klass)
      end
    end
  end
end
