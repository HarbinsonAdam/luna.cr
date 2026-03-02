require "../spec_helper"

# ----------------------------------------
# Helper methods
# ----------------------------------------

describe Luna::QueryBuilder do
  describe ".ph" do
    it "builds positional placeholders" do
      Luna::QueryBuilder.ph(1).should eq("$1")
      Luna::QueryBuilder.ph(5).should eq("$5")
    end
  end

  describe ".append_params!" do
    it "appends Array(DB::Any) params" do
      target = [] of DB::Any
      vals   = ["a@b.com", true] of DB::Any

      Luna::QueryBuilder.append_params!(target, vals)

      target.should eq(["a@b.com", true] of DB::Any)
    end

    it "appends NamedTuple params" do
      target = [] of DB::Any
      vals   = {email: "a@b.com", active: true}

      Luna::QueryBuilder.append_params!(target, vals)

      target.should eq(["a@b.com", true] of DB::Any)
    end
  end
end

# ----------------------------------------
# SELECT
# ----------------------------------------

describe Luna::QueryBuilder::Select do
  it "builds SQL without where clauses" do
    sel = Luna::QueryBuilder.select_all("users")
    sel.to_sql.should eq("SELECT * FROM users")
    sel.bound_params.should eq([] of DB::Any)
  end

  it "adds a single where clause with params" do
    sel = Luna::QueryBuilder.select_all("users").where("email = $1", "a@b.com")
    sel.to_sql.should eq("SELECT * FROM users WHERE email = $1")
    sel.bound_params.should eq(["a@b.com"] of DB::Any)
  end

  it "chains multiple where clauses and order/limit" do
    sel = Luna::QueryBuilder.select_all("users")
      .where("email = $1", "a@b.com")
      .where("is_admin = $2", true)
      .order("id DESC").limit(10).offset(5)

    sel.to_sql.should eq(
      "SELECT * FROM users WHERE email = $1 AND is_admin = $2 ORDER BY id DESC LIMIT 10 OFFSET 5"
    )
    sel.bound_params.should eq(["a@b.com", true] of DB::Any)
  end

  it "supports joins without alias" do
    sel = Luna::QueryBuilder.select_all("posts")
      .inner_join("comments", "comments.post_id = posts.id")
      .left_join("users", "users.id = posts.user_id")
      .where("posts.id = $1", 1)

    sel.to_sql.should eq(
      "SELECT * FROM posts " \
      "INNER JOIN comments ON comments.post_id = posts.id " \
      "LEFT JOIN users ON users.id = posts.user_id " \
      "WHERE posts.id = $1"
    )
    sel.bound_params.should eq([1] of DB::Any)
  end

  it "supports joins with alias" do
    sel = Luna::QueryBuilder.select_all("posts")
      .inner_join("comments", "comments.post_id = posts.id", "c")
      .left_join("users", "users.id = posts.user_id", "u")
      .where("posts.id = $1", 1)

    sel.to_sql.should eq(
      "SELECT * FROM posts " \
      "INNER JOIN comments AS c ON comments.post_id = posts.id " \
      "LEFT JOIN users AS u ON users.id = posts.user_id " \
      "WHERE posts.id = $1"
    )
    sel.bound_params.should eq([1] of DB::Any)
  end

  it "where_hash works with Hash(Symbol, DB::Any)" do
    filters = {:email => "a@b.com", :active => true} of Symbol => DB::Any
    sel = Luna::QueryBuilder.select_all("users").where_hash(filters)

    sel.to_sql.should eq(
      "SELECT * FROM users WHERE email = $1 AND active = $2"
    )
    sel.bound_params.should eq(["a@b.com", true] of DB::Any)
  end

  it "where_hash works with NamedTuple" do
    sel = Luna::QueryBuilder.select_all("users")
      .where_hash({email: "a@b.com", active: true})

    sel.to_sql.should eq(
      "SELECT * FROM users WHERE email = $1 AND active = $2"
    )
    sel.bound_params.should eq(["a@b.com", true] of DB::Any)
  end

  it "where_array works with Array(DB::Any)" do
    vals = ["a@b.com", true] of DB::Any
    sel = Luna::QueryBuilder.select_all("users")
      .where_array("email = $1 AND active = $2", vals)

    sel.to_sql.should eq(
      "SELECT * FROM users WHERE email = $1 AND active = $2"
    )
    sel.bound_params.should eq(["a@b.com", true] of DB::Any)
  end

  it "where_array works with NamedTuple" do
    vals = {email: "a@b.com", active: true}
    sel = Luna::QueryBuilder.select_all("users")
      .where_array("email = $1 AND active = $2", vals)

    sel.to_sql.should eq(
      "SELECT * FROM users WHERE email = $1 AND active = $2"
    )
    sel.bound_params.should eq(["a@b.com", true] of DB::Any)
  end

  it "select_by works with Hash(Symbol, DB::Any)" do
    filters = {:email => "a@b.com", :active => true} of Symbol => DB::Any
    sel = Luna::QueryBuilder.select_by("users", filters)

    sel.to_sql.should eq(
      "SELECT * FROM users WHERE email = $1 AND active = $2"
    )
    sel.bound_params.should eq(["a@b.com", true] of DB::Any)
  end

  it "select_by works with NamedTuple" do
    sel = Luna::QueryBuilder.select_by("users", {email: "a@b.com", active: true})

    sel.to_sql.should eq(
      "SELECT * FROM users WHERE email = $1 AND active = $2"
    )
    sel.bound_params.should eq(["a@b.com", true] of DB::Any)
  end

  it "select_by_statement works with Array(DB::Any)" do
    vals = ["a@b.com", true] of DB::Any
    sel = Luna::QueryBuilder.select_by_statement(
      "users",
      "email = $1 AND active = $2",
      vals
    )

    sel.to_sql.should eq(
      "SELECT * FROM users WHERE email = $1 AND active = $2"
    )
    sel.bound_params.should eq(["a@b.com", true] of DB::Any)
  end

  it "select_by_statement works with NamedTuple" do
    vals = {email: "a@b.com", active: true}
    sel = Luna::QueryBuilder.select_by_statement(
      "users",
      "email = $1 AND active = $2",
      vals
    )

    sel.to_sql.should eq(
      "SELECT * FROM users WHERE email = $1 AND active = $2"
    )
    sel.bound_params.should eq(["a@b.com", true] of DB::Any)
  end
end

# ----------------------------------------
# INSERT
# ----------------------------------------

describe Luna::QueryBuilder::Insert do
  it "builds insert SQL and bound params (NamedTuple data)" do
    data = {name: "Alice", age: 30}
    ins = Luna::QueryBuilder.insert_into("users", data)
    ins.to_sql.should eq("INSERT INTO users (name, age) VALUES ($1, $2) RETURNING *")
    ins.bound_params.should eq(["Alice", 30] of DB::Any)
  end

  it "builds insert SQL and bound params (Hash data)" do
    data = {:name => "Alice", :age => 30} of Symbol => DB::Any
    ins = Luna::QueryBuilder.insert_into("users", data)
    ins.to_sql.should eq("INSERT INTO users (name, age) VALUES ($1, $2) RETURNING *")
    ins.bound_params.should eq(["Alice", 30] of DB::Any)
  end

  it "supports custom returning columns" do
    data = {name: "Alice", age: 30}
    ins = Luna::QueryBuilder.insert_into("users", data).returning("id", "created_at")
    ins.to_sql.should eq("INSERT INTO users (name, age) VALUES ($1, $2) RETURNING id, created_at")
    ins.bound_params.should eq(["Alice", 30] of DB::Any)
  end
end

# ----------------------------------------
# UPDATE
# ----------------------------------------

describe Luna::QueryBuilder::Update do
  it "adds a where clause and appends params (by id, NamedTuple data)" do
    data = {status: "pending"}
    upd = Luna::QueryBuilder.update("orders", data, 99)
    upd.to_sql.should eq("UPDATE orders SET status = $1 WHERE id = $2 RETURNING *")
    upd.bound_params.should eq(["pending", 99] of DB::Any)
  end

  it "builds update SQL when data is a Hash(Symbol, DB::Any)" do
    data = {:status => "pending"} of Symbol => DB::Any
    upd = Luna::QueryBuilder.update("orders", data, 99)
    upd.to_sql.should eq("UPDATE orders SET status = $1 WHERE id = $2 RETURNING *")
    upd.bound_params.should eq(["pending", 99] of DB::Any)
  end

  it "builds update with where_hash Hash filters" do
    upd = Luna::QueryBuilder.update_where(
      "orders",
      {status: "done"},
      {:account_id => 5, :id => 1} of Symbol => DB::Any
    )
    upd.to_sql.should eq(
      "UPDATE orders SET status = $1 WHERE account_id = $2 AND id = $3 RETURNING *"
    )
    upd.bound_params.should eq(["done", 5, 1] of DB::Any)
  end

  it "builds update with where_hash NamedTuple filters" do
    upd = Luna::QueryBuilder.update_where(
      "orders",
      {status: "done"},
      {account_id: 5, id: 1}
    )
    upd.to_sql.should eq(
      "UPDATE orders SET status = $1 WHERE account_id = $2 AND id = $3 RETURNING *"
    )
    upd.bound_params.should eq(["done", 5, 1] of DB::Any)
  end

  it "chained where and where_hash combine correctly" do
    data = {status: "pending"}
    upd = Luna::QueryBuilder.update("orders", data, 99)
      .where("tenant_id = $3", 7)
      .where_hash({account_id: 5})

    upd.to_sql.should eq(
      "UPDATE orders SET status = $1 WHERE tenant_id = $3 AND account_id = $4 RETURNING *"
    )
    upd.bound_params.should eq(["pending", 99, 7, 5] of DB::Any)
  end

  it "supports custom returning columns" do
    data = {status: "pending"}
    upd = Luna::QueryBuilder.update("orders", data, 99)
      .returning("id", "updated_at")

    upd.to_sql.should eq("UPDATE orders SET status = $1 WHERE id = $2 RETURNING id, updated_at")
    upd.bound_params.should eq(["pending", 99] of DB::Any)
  end
end

# ----------------------------------------
# DELETE
# ----------------------------------------

describe Luna::QueryBuilder::Delete do
  it "builds delete SQL and bound params (by id)" do
    del = Luna::QueryBuilder.delete_from("users", 42)
    del.to_sql.should eq("DELETE FROM users WHERE id = $1 RETURNING *")
    del.bound_params.should eq([42] of DB::Any)
  end

  it "builds delete with where_hash Hash filters" do
    del = Luna::QueryBuilder.delete_where(
      "users",
      {:email => "a@b.com", :active => true} of Symbol => DB::Any
    )
    del.to_sql.should eq("DELETE FROM users WHERE email = $1 AND active = $2 RETURNING *")
    del.bound_params.should eq(["a@b.com", true] of DB::Any)
  end

  it "builds delete with where_hash NamedTuple filters" do
    del = Luna::QueryBuilder.delete_where(
      "users",
      {email: "a@b.com", active: true}
    )
    del.to_sql.should eq("DELETE FROM users WHERE email = $1 AND active = $2 RETURNING *")
    del.bound_params.should eq(["a@b.com", true] of DB::Any)
  end

  it "supports custom returning columns" do
    del = Luna::QueryBuilder.delete_from("users", 42).returning("id", "email")
    del.to_sql.should eq("DELETE FROM users WHERE id = $1 RETURNING id, email")
    del.bound_params.should eq([42] of DB::Any)
  end
end
