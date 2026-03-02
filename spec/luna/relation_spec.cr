require "../spec_helper"

class Dummy < Luna::BaseModel
  primary_key id
  attribute name : String
end

describe Luna::Relation(Dummy) do
  before_each do
    db = Luna::Setup.db_connections(:default)
    db.exec("DROP TABLE IF EXISTS dummys")
    db.exec("CREATE TABLE dummys (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT)")
    # Seed fresh, deterministic rows
    db.exec("INSERT INTO dummys (name) VALUES ('Alice')")
    db.exec("INSERT INTO dummys (name) VALUES ('Bob')")
  end

  it "retrieves all records" do
    results = Luna::Relation(Dummy).new.all
    results.size.should eq(2)
    results.first.name.should eq("Alice")
  end

  it "filters with raw where" do
    results = Luna::Relation(Dummy).new.where("name = $1", "Bob").all
    results.size.should eq(1)
    results.first.name.should eq("Bob")
  end

  it "filters with hash where" do
    results = Luna::Relation(Dummy).new.where({name: "Alice"}).all
    results.size.should eq(1)
    results.first.name.should eq("Alice")
  end

  it "returns the first record" do
    first = Luna::Relation(Dummy).new.first
    first.not_nil!.name.should eq("Alice")
  end

  it "supports aggregates" do
    r = Luna::Relation(Dummy).new
    r.count.should eq(2)
    r.min("id", as: Int64).should eq(1)
    r.max("id", as: Int64).should eq(2)
  end

  it "supports left join in aggregates" do
    db = Luna::Setup.db_connections(:default)
    db.exec("DROP TABLE IF EXISTS tags")
    db.exec("CREATE TABLE tags (id INTEGER PRIMARY KEY AUTOINCREMENT, d_id INTEGER, name TEXT)")
    db.exec("INSERT INTO tags (d_id, name) VALUES (1, 'tag-a')")

    r = Luna::Relation(Dummy).new.left_join("tags", "tags.d_id = dummys.id")
    r.count.should eq(2)
  end
end
