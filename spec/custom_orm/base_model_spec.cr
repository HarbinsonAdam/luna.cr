require "../spec_helper"

class TestModel < CustomOrm::BaseModel
  connection :reports
end

class Kurwa < CustomOrm::BaseModel
  primary_key id
  attribute name : String
  attribute active : Bool, default: false
end

describe "BaseModel" do
  describe "connection" do
    it "switches db when using the connection macro" do
      TestModel.db_connection.should eq(CustomOrm::Setup.db_connections(:reports))
    end

    it "uses the default connection by default" do
      Kurwa.db_connection.should eq(CustomOrm::Setup.db_connections(:default))
    end
  end

  describe "crud methods" do
    before_all do
      db = CustomOrm::Setup.db_connections(:default)
      db.exec("CREATE TABLE IF NOT EXISTS kurwas (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, active BOOLEAN)")
    end

    before_each do
      Kurwa.db_connection.exec("DELETE FROM kurwas")
    end

    it "saves a new record with save" do
      m = Kurwa.new(name: "Delta", active: true)
      m.save
      m.id.should_not be_nil
      k = Kurwa.find_by({name: "Delta"})
      k.should be_a(Kurwa)
      k.not_nil!.active.should be_true
    end

    it "updates an existing record with save" do
      Kurwa.new(name: "Epsilon", active: false).save
      m = Kurwa.find_by!({name: "Epsilon"})
      m.active = true
      m.save
      active = Kurwa.db_connection.query_one("SELECT active FROM kurwas WHERE name = ?", args: ["Epsilon"], as: Bool)
      active.should be_true
    end

    it "updates an existing record with update method" do
      Kurwa.new(name: "Zeta", active: true).save
      m = Kurwa.find_by!({name: "Zeta"})
      m.active = false
      m.update
      active = Kurwa.db_connection.query_one("SELECT active FROM kurwas WHERE name = ?", args: ["Zeta"], as: Bool)
      active.should be_false
    end

    it "destroys an existing record" do
      Kurwa.new(name: "Theta", active: true).save
      m = Kurwa.find_by!({name: "Theta"})
      m.destroy
      count = Kurwa.db_connection.query_one("SELECT COUNT(*) FROM kurwas WHERE name = ?", args: ["Theta"], as: Int64)
      count.should eq(0)
    end

    it "supports aggregates & helpers" do
      Kurwa.new(name: "A", active: true).save
      Kurwa.new(name: "B", active: false).save
      Kurwa.count.should eq(2)
      Kurwa.exists?.should be_true
      Kurwa.exists?({name: "ZZZ"}).should be_false
      names = Kurwa.pluck("name", as: String)
      names.sort!.should eq(["A", "B"])
    end

    it "executes inside a transaction" do
      begin
        Kurwa.transaction do
          Kurwa.new(name: "TX", active: true).save
          raise "boom"
        end
      rescue
        # noop
      end
      Kurwa.exists?({name: "TX"}).should be_false
    end
  end
end
