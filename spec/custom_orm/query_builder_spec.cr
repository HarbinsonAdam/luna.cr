require "../spec_helper"

describe CustomOrm::QueryBuilder::Select do
  it "builds SQL without where clauses" do
    sel = CustomOrm::QueryBuilder.select_all("users")
    sel.to_sql.should eq("SELECT * FROM users")
    sel.bound_params.should eq([] of DB::Any)
  end

  it "adds a single where clause with params" do
    sel = CustomOrm::QueryBuilder.select_all("users").where("email = $1", "a@b.com")
    sel.to_sql.should eq("SELECT * FROM users WHERE email = $1")
    sel.bound_params.should eq(["a@b.com"] of DB::Any)
  end

  it "chains multiple where clauses with params" do
    sel = CustomOrm::QueryBuilder.select_all("users")
          .where("email = $1", "a@b.com")
          .where("is_admin = $2", true)
    sel.to_sql.should eq(
      "SELECT * FROM users WHERE email = $1 AND is_admin = $2"
    )
    sel.bound_params.should eq(["a@b.com", true] of DB::Any)
  end
end

describe CustomOrm::QueryBuilder::Insert do
  it "builds insert SQL and bound params" do
    data = {name: "Alice", age: 30}
    ins = CustomOrm::QueryBuilder.insert_into("users", data)
    ins.to_sql.should eq("INSERT INTO users (name, age) VALUES ($1, $2) RETURNING *")
    ins.bound_params.should eq(["Alice", 30] of DB::Any)
  end
end

describe CustomOrm::QueryBuilder::Update do
  it "adds a where clause and appends params" do
    data = {status: "pending"}
    upd = CustomOrm::QueryBuilder.update("orders", data, 99)
    upd.to_sql.should eq("UPDATE orders SET status = $1 WHERE id = $2")
    upd.bound_params.should eq(["pending", 99] of DB::Any)
  end
end

describe CustomOrm::QueryBuilder::Delete do
  it "builds delete SQL and bound params" do
    del = CustomOrm::QueryBuilder.delete_from("users", 42)
    del.to_sql.should eq("DELETE FROM users WHERE id = $1")
    del.bound_params.should eq([42] of DB::Any)
  end
end