require "../spec_helper"

# SELECT

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

  it "chains multiple where clauses and order/limit" do
    sel = CustomOrm::QueryBuilder.select_all("users")
      .where("email = $1", "a@b.com")
      .where("is_admin = $2", true)
      .order("id DESC").limit(10).offset(5)
    sel.to_sql.should eq("SELECT * FROM users WHERE email = $1 AND is_admin = $2 ORDER BY id DESC LIMIT 10 OFFSET 5")
    sel.bound_params.should eq(["a@b.com", true] of DB::Any)
  end

  it "supports joins" do
    sel = CustomOrm::QueryBuilder.select_all("posts")
      .inner_join("comments", "comments.post_id = posts.id")
      .left_join("users", "users.id = posts.user_id")
      .where("posts.id = $1", 1)
    sel.to_sql.should eq("SELECT * FROM posts INNER JOIN comments ON comments.post_id = posts.id LEFT JOIN users ON users.id = posts.user_id WHERE posts.id = $1")
    sel.bound_params.should eq([1] of DB::Any)
  end
end

# INSERT

describe CustomOrm::QueryBuilder::Insert do
  it "builds insert SQL and bound params" do
    data = {name: "Alice", age: 30}
    ins = CustomOrm::QueryBuilder.insert_into("users", data)
    ins.to_sql.should eq("INSERT INTO users (name, age) VALUES ($1, $2) RETURNING *")
    ins.bound_params.should eq(["Alice", 30] of DB::Any)
  end
end

# UPDATE

describe CustomOrm::QueryBuilder::Update do
  it "adds a where clause and appends params (by id)" do
    data = {status: "pending"}
    upd = CustomOrm::QueryBuilder.update("orders", data, 99)
    upd.to_sql.should eq("UPDATE orders SET status = $1 WHERE id = $2 RETURNING *")
    upd.bound_params.should eq(["pending", 99] of DB::Any)
  end

  it "builds update with where_hash" do
    upd = CustomOrm::QueryBuilder.update_where("orders", {status: "done"}, {account_id: 5, id: 1})
    upd.to_sql.should eq("UPDATE orders SET status = $1 WHERE account_id = $2 AND id = $3 RETURNING *")
    upd.bound_params.should eq(["done", 5, 1] of DB::Any)
  end
end

# DELETE

describe CustomOrm::QueryBuilder::Delete do
  it "builds delete SQL and bound params (by id)" do
    del = CustomOrm::QueryBuilder.delete_from("users", 42)
    del.to_sql.should eq("DELETE FROM users WHERE id = $1 RETURNING *")
    del.bound_params.should eq([42] of DB::Any)
  end

  it "builds delete with where_hash" do
    del = CustomOrm::QueryBuilder.delete_where("users", {email: "a@b.com", active: true})
    del.to_sql.should eq("DELETE FROM users WHERE email = $1 AND active = $2 RETURNING *")
    del.bound_params.should eq(["a@b.com", true] of DB::Any)
  end
end
