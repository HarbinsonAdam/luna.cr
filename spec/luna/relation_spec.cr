require "../spec_helper"

class Dummy < Luna::BaseModel
  primary_key id
  attribute name : String
end

describe Luna::Relation(Dummy) do
  before_each do
    db = Luna::Setup.db_connections(:default)
    db.exec("DROP TABLE IF EXISTS dummys")
    db.exec("CREATE TABLE dummys (#{SpecDb.primary_key}, #{SpecDb.text("name")})")
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
    results = Luna::Relation(Dummy).new.where("name = #{SpecDb.placeholder(1)}", "Bob").all
    results.size.should eq(1)
    results.first.name.should eq("Bob")
  end

  it "filters with hash where" do
    results = Luna::Relation(Dummy).new.where({name: "Alice"}).all
    results.size.should eq(1)
    results.first.name.should eq("Alice")
  end

  it "keeps existing clauses when chaining hash where" do
    results = Luna::Relation(Dummy).new
      .where("id > #{SpecDb.placeholder(1)}", 0)
      .where({name: "Bob"})
      .all
    results.size.should eq(1)
    results.first.name.should eq("Bob")
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
    db.exec("CREATE TABLE tags (#{SpecDb.primary_key}, #{SpecDb.integer("d_id")}, #{SpecDb.text("name")})")
    db.exec("INSERT INTO tags (d_id, name) VALUES (1, 'tag-a')")

    r = Luna::Relation(Dummy).new.left_join("tags", "tags.d_id = dummys.id")
    r.count.should eq(2)
  end
end
