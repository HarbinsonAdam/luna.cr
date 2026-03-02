require "../spec_helper"

class TestModel < Luna::BaseModel
  connection :reports
end

class Website < Luna::BaseModel
  primary_key id
  attribute name : String
  attribute active : Bool, default: false
end

describe "BaseModel" do
  describe "connection" do
    it "switches db when using the connection macro" do
      TestModel.db_connection.should eq(Luna::Setup.db_connections(:reports))
    end

    it "uses the default connection by default" do
      Website.db_connection.should eq(Luna::Setup.db_connections(:default))
    end
  end

  describe "crud methods" do
    before_all do
      db = Luna::Setup.db_connections(:default)
      db.exec("CREATE TABLE IF NOT EXISTS websites (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, active BOOLEAN)")
    end

    before_each do
      Website.db_connection.exec("DELETE FROM websites")
    end

    it "saves a new record with save" do
      m = Website.new(name: "Delta", active: true)
      m.save
      m.id.should_not be_nil
      k = Website.find_by({name: "Delta"})
      k.should be_a(Website)
      k.not_nil!.active.should be_true
    end

    it "updates an existing record with save" do
      Website.new(name: "Epsilon", active: false).save
      m = Website.find_by!({name: "Epsilon"})
      m.active = true
      m.save
      active = Website.db_connection.query_one("SELECT active FROM websites WHERE name = ?", args: ["Epsilon"], as: Bool)
      active.should be_true
    end

    it "updates an existing record with update method" do
      Website.new(name: "Zeta", active: true).save
      m = Website.find_by!({name: "Zeta"})
      m.active = false
      m.update
      active = Website.db_connection.query_one("SELECT active FROM websites WHERE name = ?", args: ["Zeta"], as: Bool)
      active.should be_false
    end

    it "destroys an existing record" do
      Website.new(name: "Theta", active: true).save
      m = Website.find_by!({name: "Theta"})
      m.destroy
      count = Website.db_connection.query_one("SELECT COUNT(*) FROM websites WHERE name = ?", args: ["Theta"], as: Int64)
      count.should eq(0)
    end

    it "supports aggregates & helpers" do
      Website.new(name: "A", active: true).save
      Website.new(name: "B", active: false).save
      Website.count.should eq(2)
      Website.exists?.should be_true
      Website.exists?({name: "ZZZ"}).should be_false
      names = Website.pluck("name", as: String)
      names.sort!.should eq(["A", "B"])
    end

    it "executes inside a transaction" do
      begin
        Website.transaction do
          Website.new(name: "TX", active: true).save
          raise "boom"
        end
      rescue
        # noop
      end
      Website.exists?({name: "TX"}).should be_false
    end
  end
end
