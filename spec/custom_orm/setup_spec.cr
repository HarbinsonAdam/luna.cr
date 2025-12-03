require "../spec_helper"

describe CustomOrm::Setup do
  it "registers and retrieves a named connection" do
    CustomOrm::Setup.register :alt, "sqlite3://#{DB_FILE}"
    db = CustomOrm::Setup.db_connections :alt
    db.should be_a(DB::Database)
  end

  it "raises for unregistered connection" do
    expect_raises(Exception) { CustomOrm::Setup.db_connections :missing }
  end

  it "provides a default_connection alias" do
    CustomOrm::Setup.register :default, "sqlite3://#{DB_FILE}"
    CustomOrm::Setup.default_connection.should eq(CustomOrm::Setup.db_connections :default)
  end
end
