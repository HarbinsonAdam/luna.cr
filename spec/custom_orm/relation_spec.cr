require "../spec_helper"

# Dummy model for testing
class Dummy < CustomOrm::BaseModel
  primary_key id
  attribute name : String
end

describe CustomOrm::Relation(Dummy) do
  Spec.before_suite do
    db = CustomOrm::Setup.db_connections(:default)
    # prepare table and data
    db.exec("CREATE TABLE dummys (id INTEGER, name TEXT)")
    db.exec("INSERT INTO dummys (id, name) VALUES (1, 'Alice')")
    db.exec("INSERT INTO dummys (id, name) VALUES (2, 'Bob')")
  end

  it "retrieves all records" do
    results = CustomOrm::Relation(Dummy).new.all
    results.map(&.attributes).to_json.should eq([
      {"id" => 1, "name" => "Alice"},
      {"id" => 2, "name" => "Bob"}
  ].to_json)
  end

  it "filters with raw where" do
    results = CustomOrm::Relation(Dummy)
                  .new
                 .where("id = $1", 2)
                 .all
    results.map(&.attributes).to_json.should eq([{"id" => 2, "name" => "Bob"}].to_json)
  end

  it "filters with hash where" do
    results = CustomOrm::Relation(Dummy)
    .new
                 .where({id: 1})
                 .all
    results.map(&.attributes).to_json.should eq([{"id" => 1, "name" => "Alice"}].to_json)
  end

  it "returns the first record" do
    first = CustomOrm::Relation(Dummy).new.first
    first.attributes.to_json.should eq({"id" => 1, "name" => "Alice"}.to_json)
  end
end
