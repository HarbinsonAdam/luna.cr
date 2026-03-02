# Luna.cr

Luna.cr is a Crystal ORM that provides an Active Record pattern implementation inspired by Ruby on Rails. It's built on top of SpiderGazelle's ActiveModel and offers database operations similar to Rails Active Record.

## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     luna:
       github: HarbinsonAdam/luna.cr
   ```

2. Run `shards install`

## Usage

```crystal
require "luna"
```

Luna.cr provides a familiar interface for database operations with ActiveRecord-style syntax:

```crystal
class User < Luna::BaseModel
  primary_key id
  attribute name : String
  attribute email : String
  attribute age : Int32
  attribute admin : Bool, default: false
end

# Create
user = User.new(name: "John Doe", email: "john@example.com", age: 30)
user.save

# Read
user = User.find(1) # User | Nil
user = User.find!(1) # User | RecordNotFound
users = User.all # Array(User)

# Update
user.update(name: "Jane Doe")

# Delete
user.destroy
```

### Migrations

Luna.cr supports database migrations:

```crystal
# Create a migration
class V00000000000001_CreateUsers < Luna::Migration
  def up
    create_table :users, id: true do |t|
      t.text :name, null: false
      t.text :email, null: false
      t.integer :age
      t.boolean :active, default: true
      t.timestamps
    end

    add_index :users, :email, unique: true
  end

  def down
    remove_index :users, :email

    drop_table :users
  end
end
```

## Development

Luna.cr is currently in development. The project is mirrored from a private GitLab repository to GitHub for public access.

## Contributing

1. Fork it (<https://github.com/HarbinsonAdam/luna.cr/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Adam Harbinson](https://github.com/HarbinsonAdam) - creator and maintainer
