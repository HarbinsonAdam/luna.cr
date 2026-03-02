# Luna.cr

Luna is an ActiveRecord-style ORM for Crystal, built on top of `active-model`.

It supports:
- Model persistence (`save`, `update`, `destroy`)
- Relation-style querying (`where`, `order`, `limit`, aggregates)
- Associations (`belongs_to`, `has_one`, `has_many`)
- Transactions
- Migrations
- Single Table Inheritance (STI)

## Installation

Add to `shard.yml`:

```yaml
dependencies:
  luna:
    github: HarbinsonAdam/luna.cr
```

Then:

```bash
shards install
```

## Setup

Register at least one connection before using models:

```crystal
require "luna"

Luna::Setup.register :default, "sqlite3:./db/app.db"
# Optional additional connections
Luna::Setup.register :reports, "sqlite3:./db/reports.db"
```

Supported URL schemes include `sqlite3:`, `postgres://`, and `mysql://`.

## Defining Models

```crystal
class User < Luna::BaseModel
  primary_key id
  attribute name : String
  attribute email : String
  attribute active : Bool, default: true
end
```

Use a non-default connection:

```crystal
class AuditLog < Luna::BaseModel
  connection :reports
  primary_key id
  attribute message : String
end
```

## CRUD

```crystal
# Create
user = User.new(name: "Ada", email: "ada@example.com")
user.save

# Read
found = User.find(user.id.not_nil!)     # User?
found! = User.find!(user.id.not_nil!)   # raises Luna::RecordNotFound if missing

# Update
found!.active = false
found!.save

# Delete
found!.destroy
```

## Querying (Relation API)

`all` and `where` return a relation, so you can chain:

```crystal
relation = User.where({active: true}).order("id DESC").limit(10)
users = relation.all
first_user = relation.first
```

Other helpers:

```crystal
User.count
User.exists?
User.exists?({email: "ada@example.com"})
User.pluck("email", as: String)
User.sum("id", as: Int64)
User.avg("id", as: Float64)
User.min("id", as: Int64)
User.max("id", as: Int64)
```

## Associations

```crystal
class Author < Luna::BaseModel
  primary_key id
  attribute name : String
  has_many posts, Post
end

class Post < Luna::BaseModel
  primary_key id
  attribute author_id : Int64?
  attribute title : String
  belongs_to author, Author
end
```

Eager loading:

```crystal
posts = Post.order("id ASC").includes(:author).all
```

Nested eager loading is supported:

```crystal
authors = Author.includes(posts: :comments).all
```

## Transactions

Global transaction:

```crystal
Luna.transaction do
  User.new(name: "A", email: "a@example.com").save
  User.new(name: "B", email: "b@example.com").save
end
```

Model-scoped transaction (uses model connection):

```crystal
User.transaction do
  # ...
end
```

Rollback without bubbling an error:

```crystal
Luna.transaction do
  User.new(name: "Temp", email: "temp@example.com").save
  raise Luna::Rollback.new
end
```

## STI (Single Table Inheritance)

Parent model defines discriminator column with `sti`.
Child models define type with `sti_type`.

```crystal
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
```

Behavior:
- `Dog`/`Cat` use the parent table
- Saving a child sets `kind` automatically
- Querying `Animal` hydrates the correct subclass
- Querying `Dog` or `Cat` automatically scopes by type

## Migrations

Define a migration by inheriting `Luna::BaseMigration`.
Migrations auto-register when inherited.

```crystal
class V20260101000000_CreateUsers < Luna::BaseMigration
  def change
    create_table :users, id: true do |t|
      t.string :name, null: false
      t.string :email, null: false
      t.boolean :active, default: true
      t.timestamps
    end

    add_index :users, :email, unique: true
  end
end
```

Run migrations:

```crystal
runner = Luna::MigrationRunner.new(:default)
runner.run_migrations
```

## Development

Run specs:

```bash
crystal spec
```

Luna.cr is currently in development. The project is mirrored from a private GitLab repository to GitHub for public access.

## Contributors

- [Adam Harbinson](https://github.com/HarbinsonAdam) - creator and maintainer
