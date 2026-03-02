require "../spec_helper"

describe Luna::Setup do
  it "registers and retrieves a named connection" do
    Luna::Setup.register :alt, "sqlite3://#{DB_FILE}"
    db = Luna::Setup.db_connections :alt
    db.should be_a(DB::Database)
  end

  it "raises for unregistered connection" do
    expect_raises(Exception) { Luna::Setup.db_connections :missing }
  end

  it "provides a default_connection alias" do
    Luna::Setup.register :default, "sqlite3://#{DB_FILE}"
    Luna::Setup.default_connection.should eq(Luna::Setup.db_connections :default)
  end
end
