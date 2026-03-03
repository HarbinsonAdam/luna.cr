require "../spec_helper"

class TestModel < Luna::BaseModel
  connection :reports
end

class Website < Luna::BaseModel
  primary_key id
  attribute name : String
  attribute active : Bool, default: false
end

class CachedWebsite < Luna::BaseModel
  primary_key id
  cache_by_id 1, 2
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
      db.exec("CREATE TABLE IF NOT EXISTS cached_websites (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, active BOOLEAN)")
    end

    before_each do
      Website.db_connection.exec("DELETE FROM websites")
      CachedWebsite.db_connection.exec("DELETE FROM cached_websites")
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

    it "supports relation-style class chaining" do
      Website.new(name: "A", active: true).save
      Website.new(name: "B", active: false).save
      results = Website.where({active: true}).order("id ASC").all
      results.size.should eq(1)
      results.first.name.should eq("A")
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

    it "rolls back and swallows Luna::Rollback" do
      Luna.transaction do
        Website.new(name: "TX2", active: true).save
        raise Luna::Rollback.new
      end
      Website.exists?({name: "TX2"}).should be_false
    end

    it "caches records fetched by id" do
      model = CachedWebsite.new(name: "Cached A", active: true)
      model.save
      id = model.id

      first = CachedWebsite.find!(id)
      first.name.should eq("Cached A")

      CachedWebsite.db_connection.exec("UPDATE cached_websites SET name = ? WHERE id = ?", args: ["Changed In DB", id])

      cached = CachedWebsite.find!(id)
      cached.name.should eq("Cached A")
    end

    it "expires cached records by ttl" do
      model = CachedWebsite.new(name: "TTL Name", active: true)
      model.save
      id = model.id

      CachedWebsite.find!(id)
      CachedWebsite.db_connection.exec("UPDATE cached_websites SET name = ? WHERE id = ?", args: ["Fresh Name", id])

      sleep 1100.milliseconds

      reloaded = CachedWebsite.find!(id)
      reloaded.name.should eq("Fresh Name")
    end

    it "evicts least recently used records when cache limit is exceeded" do
      a = CachedWebsite.new(name: "A", active: true); a.save
      b = CachedWebsite.new(name: "B", active: true); b.save
      c = CachedWebsite.new(name: "C", active: true); c.save

      CachedWebsite.find!(a.id)
      CachedWebsite.find!(b.id)
      CachedWebsite.find!(c.id)

      CachedWebsite.db_connection.exec("UPDATE cached_websites SET name = ? WHERE id = ?", args: ["A From DB", a.id])

      reloaded = CachedWebsite.find!(a.id)
      reloaded.name.should eq("A From DB")
    end

    it "keeps cache in sync after update and save" do
      model = CachedWebsite.new(name: "Sync", active: false)
      model.save
      id = model.id

      loaded = CachedWebsite.find!(id)
      loaded.active = true
      loaded.save

      cached = CachedWebsite.find!(id)
      cached.active.should be_true
    end
  end
end
