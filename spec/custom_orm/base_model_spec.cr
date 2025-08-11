require "../spec_helper"

class TestModel < CustomOrm::BaseModel
  connection :test
end

class Kurwa < CustomOrm::BaseModel
  primary_key id
  attribute name : String
  attribute active : Bool, default: false
end

describe "BaseModel" do
  describe "connection"do
    it "switches CONNECTION when using the connection macro" do
      TestModel.db_connection.should eq(CustomOrm::Setup.db_connections(:test))
    end

    it "uses the default connection by default" do
      Kurwa.db_connection.should eq(CustomOrm::Setup.db_connections(:default))
    end
  end

  describe "crud methods" do
    Spec.before_suite do
      db = CustomOrm::Setup.db_connections(:default)
      res = db.exec("CREATE TABLE kurwas (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, active INTEGER)")
    end

    it "saves a new record with save" do
      m = Kurwa.new(name: "Delta", active: true)
      m.save
      m.id.should_not be_nil
      k = Kurwa.find_by({name: "Delta"})
      k.should be_a(Kurwa)
    end

    it "updates an existing record with save" do
      Kurwa.new(name: "Epsilon", active: false).save
      m = Kurwa.find_by({name: "Epsilon"})
      m.active = true
      m.save
      active = Kurwa.db_connection.query_one("SELECT active FROM kurwas WHERE name = $1", "Epsilon", as: Bool)
      active.should be_true
    end

    it "updates an existing record with update method" do
      Kurwa.new(name: "Zeta", active: true).save
      m = Kurwa.find_by({name: "Zeta"})
      m.active = false
      m.update
      active = Kurwa.db_connection.query_one("SELECT active FROM kurwas WHERE name = $1", "Zeta", as: Bool)
      active.should be_false
    end

    it "destroys an existing record" do
      Kurwa.new(name: "Theta", active: true).save
      m = Kurwa.find_by({name: "Theta"})
      m.destroy
      count = Kurwa.db_connection.query_one("SELECT COUNT(*) FROM kurwas WHERE name = $1", "Theta", as: Int64)
      count.should eq(0)
    end
  end
end
