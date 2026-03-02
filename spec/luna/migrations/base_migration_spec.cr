require "spec"

# Adjust the require path above to match your project layout

describe Luna::Migrations::TableDefinition do
  describe "#primary_key" do
    it "builds a BIGSERIAL primary key for Postgres" do
      td = Luna::Migrations::TableDefinition.new(Luna::SQL::Dialect::Pg)
      td.primary_key
      td.columns.should eq(["id BIGSERIAL PRIMARY KEY"])
    end

    it "builds a BIGINT auto_increment primary key for MySQL" do
      td = Luna::Migrations::TableDefinition.new(Luna::SQL::Dialect::Mysql)
      td.primary_key("pk")
      td.columns.should eq(["pk BIGINT PRIMARY KEY AUTO_INCREMENT"])
    end

    it "builds an INTEGER autoincrement primary key for SQLite" do
      td = Luna::Migrations::TableDefinition.new(Luna::SQL::Dialect::Sqlite)
      td.primary_key
      td.columns.should eq(["id INTEGER PRIMARY KEY AUTOINCREMENT"])
    end
  end

  describe "#string" do
    it "uses VARCHAR(255) by default on Postgres" do
      td = Luna::Migrations::TableDefinition.new(Luna::SQL::Dialect::Pg)
      td.string(:name)
      td.columns.first.should eq(%(name VARCHAR(255)))
    end

    it "respects limit on MySQL" do
      td = Luna::Migrations::TableDefinition.new(Luna::SQL::Dialect::Mysql)
      td.string(:email, limit: 128)
      td.columns.first.should eq(%(email VARCHAR(128)))
    end

    it "uses TEXT on SQLite" do
      td = Luna::Migrations::TableDefinition.new(Luna::SQL::Dialect::Sqlite)
      td.string(:title)
      td.columns.first.should eq(%(title TEXT))
    end
  end

  describe "#boolean" do
    it "maps boolean to BOOLEAN on Postgres with TRUE default" do
      td = Luna::Migrations::TableDefinition.new(Luna::SQL::Dialect::Pg)
      td.boolean(:active, null: false, default: true)
      td.columns.first.should eq(%(active BOOLEAN NOT NULL DEFAULT TRUE))
    end

    it "maps boolean to INTEGER on SQLite with numeric default" do
      td = Luna::Migrations::TableDefinition.new(Luna::SQL::Dialect::Sqlite)
      td.boolean(:active, null: false, default: false)
      td.columns.first.should eq(%(active INTEGER NOT NULL DEFAULT 0))
    end
  end

  describe "#datetime" do
    it "uses TIMESTAMPTZ with CURRENT_TIMESTAMP default on Postgres" do
      td = Luna::Migrations::TableDefinition.new(Luna::SQL::Dialect::Pg)
      td.datetime(:created_at, null: false, default_now: true)

      td.columns.first.should eq(%(created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP))
    end

    it "uses DATETIME on SQLite" do
      td = Luna::Migrations::TableDefinition.new(Luna::SQL::Dialect::Sqlite)
      td.datetime(:created_at, null: true, default_now: false)

      td.columns.first.should eq(%(created_at DATETIME))
    end
  end

  describe "#timestamps" do
    it "adds created_at and updated_at with default_now=true" do
      td = Luna::Migrations::TableDefinition.new(Luna::SQL::Dialect::Pg)
      td.timestamps

      td.columns.size.should eq(2)
      td.columns[0].should eq(%(created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP))
      td.columns[1].should eq(%(updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP))
    end
  end
end

describe Luna::Migrations::TypeSql do
  describe ".sql_type_for" do
    it "maps :string to TEXT for sqlite" do
      t = Luna::Migrations::TypeSql.sql_type_for(:string, Luna::SQL::Dialect::Sqlite, {} of Symbol => DB::Any)
      t.should eq("TEXT")
    end

    it "maps :string to VARCHAR with limit for Postgres" do
      opts = {:limit => 42} of Symbol => DB::Any
      t = Luna::Migrations::TypeSql.sql_type_for(:string, Luna::SQL::Dialect::Pg, opts)
      t.should eq("VARCHAR(42)")
    end

    it "maps :json to JSONB for Postgres" do
      t = Luna::Migrations::TypeSql.sql_type_for(:json, Luna::SQL::Dialect::Pg, {} of Symbol => DB::Any)
      t.should eq("JSONB")
    end

    it "raises on unknown type" do
      expect_raises(Exception, /Unknown column type/) do
        Luna::Migrations::TypeSql.sql_type_for(:wtf, Luna::SQL::Dialect::Pg, {} of Symbol => DB::Any)
      end
    end
  end

  describe ".build_col" do
    it "adds NOT NULL and DEFAULT for a string value" do
      col = Luna::Migrations::TypeSql.build_col(:name, "TEXT", Luna::SQL::Dialect::Sqlite, false, "hello")
      col.should eq(%(name TEXT NOT NULL DEFAULT 'hello'))
    end

    it "escapes single quotes in default string" do
      col = Luna::Migrations::TypeSql.build_col(:name, "TEXT", Luna::SQL::Dialect::Pg, true, "O'Hara")
      col.should eq(%(name TEXT DEFAULT 'O''Hara'))
    end

    it "handles boolean default for Postgres" do
      col = Luna::Migrations::TypeSql.build_col(:active, "BOOLEAN", Luna::SQL::Dialect::Pg, false, true)
      col.should eq(%(active BOOLEAN NOT NULL DEFAULT TRUE))
    end
  end
end

describe Luna::Migrations::ChangeTable do
  it "builds ADD and DROP statements" do
    ct = Luna::Migrations::ChangeTable.new("users", Luna::SQL::Dialect::Pg)

    ct.add(:age, :integer, null: false, default: 18)
    ct.remove(:old_column)
    ct.rename(:foo, :bar)

    ct.statements.size.should eq(3)
    ct.statements[0].should eq("ALTER TABLE users ADD COLUMN age INTEGER NOT NULL DEFAULT 18")
    ct.statements[1].should eq("ALTER TABLE users DROP COLUMN old_column")
    ct.statements[2].should eq("ALTER TABLE users RENAME COLUMN foo TO bar")
  end

  it "raises if remove(column) is used with sqlite" do
    ct = Luna::Migrations::ChangeTable.new("users", Luna::SQL::Dialect::Sqlite)

    expect_raises(Exception, /SQLite remove\(column\) not supported/) do
      ct.remove(:old_column)
    end
  end
end
