require "../spec_helper"

describe CustomOrm::Setup do
  it "registers and retrieves a named pool" do
    CustomOrm::Setup.register :test, "sqlite3://#{DB_FILE}"
    pool = CustomOrm::Setup.db_connections :test
    pool.should be_a(DB::Database)
  end

  it "raises if retrieving an unregistered connection" do
    expect_raises(Exception){ CustomOrm::Setup.db_connections :missing }
  end

  it "provides a default_pool alias" do
    CustomOrm::Setup.register :default, "sqlite3://#{DB_FILE}"
    CustomOrm::Setup.default_connection.should eq(CustomOrm::Setup.db_connections :default)
  end
end
