require "../spec_helper"

class Animal < Luna::BaseModel
  primary_key id
  sti kind
  attribute name : String
end

class Dog < Animal
  sti_type :dog
  attribute bark_volume : Int64?
end

class Cat < Animal
  sti_type :cat
  attribute lives_left : Int64?
end

describe "STI" do
  before_each do
    db = Luna::Setup.db_connections(:default)
    db.exec("DROP TABLE IF EXISTS animals")
    db.exec("CREATE TABLE animals (id INTEGER PRIMARY KEY AUTOINCREMENT, kind TEXT, name TEXT, bark_volume INTEGER, lives_left INTEGER)")
  end

  it "uses parent table for STI children" do
    Dog.table_name.should eq("animals")
    Cat.table_name.should eq("animals")
  end

  it "persists child type automatically" do
    dog = Dog.new(name: "Rex", bark_volume: 5)
    dog.save

    db_type = Luna::Setup.db_connections(:default).query_one("SELECT kind FROM animals WHERE id = ?", args: [dog.id], as: String)
    db_type.should eq("dog")
  end

  it "instantiates subclasses when loading through parent relation" do
    Dog.new(name: "Bolt", bark_volume: 9).save
    Cat.new(name: "Milo", lives_left: 7).save
    Animal.__sti_class_for("dog").should eq(Dog)
    Animal.__sti_class_for("cat").should eq(Cat)

    animals = Animal.order("id ASC").all
    animals.size.should eq(2)
    animals[0].should be_a(Dog)
    animals[1].should be_a(Cat)
  end

  it "applies child relation scoping by sti type" do
    Dog.new(name: "D1", bark_volume: 1).save
    Cat.new(name: "C1", lives_left: 8).save

    Dog.count.should eq(1)
    Cat.count.should eq(1)
    Dog.all.first.not_nil!.name.should eq("D1")
    Dog.find(Cat.all.first.not_nil!.id).should be_nil
  end
end
