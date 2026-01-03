require "../spec_helper"

# ----------------------------------------
# Test models
# ----------------------------------------

class Author < CustomOrm::BaseModel
  primary_key id
  attribute name : String

  has_many posts, klass: Post, foreign_key: author_id
  has_one profile, klass: Profile, foreign_key: author_id
end

class Profile < CustomOrm::BaseModel
  primary_key id
  attribute author_id : Int64
  attribute bio : String

  belongs_to author, klass: Author, foreign_key: author_id
end

class Post < CustomOrm::BaseModel
  primary_key id
  attribute author_id : Int64?
  attribute title : String

  belongs_to author, klass: Author, foreign_key: author_id
  has_many comments, klass: Comment, foreign_key: post_id
end

class Comment < CustomOrm::BaseModel
  primary_key id
  attribute post_id : Int64
  attribute body : String
end

# ----------------------------------------
# Helper: count queries
# ----------------------------------------
#
# This assumes you can wrap a DB::Connection and intercept #query/#exec.
# If your DB adapter doesn't let you easily wrap, the tests still pass
# without the "query count" expectations by removing those parts.
#
# ----------------------------------------
# Spec-only query counter (instrument Exec)
# ----------------------------------------
module CustomOrm::Exec
  @@__spec_query_count : Int32 = 0

  def self.__spec_reset_query_count
    @@__spec_query_count = 0
  end

  def self.__spec_query_count : Int32
    @@__spec_query_count
  end

  def self.query_all(db : DB::Database, sql : String, params : Array(DB::Any),
                     dialect : CustomOrm::SQL::Dialect, &block : DB::ResultSet ->)
    @@__spec_query_count += 1
    previous_def(db, sql, params, dialect) do |rs|
      yield rs
    end
  end

  def self.exec(db : DB::Database, sql : String, params : Array(DB::Any),
                dialect : CustomOrm::SQL::Dialect)
    @@__spec_query_count += 1
    previous_def
  end

  def self.query_one(db : DB::Database, sql : String, params : Array(DB::Any),
                     dialect : CustomOrm::SQL::Dialect, as : T.class) : T forall T
    @@__spec_query_count += 1
    previous_def
  end
end

# ----------------------------------------
# Specs
# ----------------------------------------

describe "Associations" do
  before_each do
    db = CustomOrm::Setup.db_connections(:default)
    db.exec("DROP TABLE IF EXISTS comments")
    db.exec("DROP TABLE IF EXISTS posts")
    db.exec("DROP TABLE IF EXISTS profiles")
    db.exec("DROP TABLE IF EXISTS authors")

    db.exec("CREATE TABLE IF NOT EXISTS authors  (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT)")
    db.exec("CREATE TABLE IF NOT EXISTS profiles (id INTEGER PRIMARY KEY AUTOINCREMENT, author_id INTEGER NOT NULL, bio TEXT)")
    db.exec("CREATE TABLE IF NOT EXISTS posts    (id INTEGER PRIMARY KEY AUTOINCREMENT, author_id INTEGER, title TEXT)")
    db.exec("CREATE TABLE IF NOT EXISTS comments (id INTEGER PRIMARY KEY AUTOINCREMENT, post_id INTEGER NOT NULL, body TEXT)")

    # Seed:
    # Author 1 has profile + 2 posts (post 1 has 2 comments, post 2 has 1 comment)
    # Author 2 has 1 post (no comments, no profile)
    db.exec("INSERT INTO authors (name) VALUES ('Ada')")
    db.exec("INSERT INTO authors (name) VALUES ('Lydia')")

    db.exec("INSERT INTO profiles (author_id, bio) VALUES (1, 'hello world')")

    db.exec("INSERT INTO posts (author_id, title) VALUES (1, 'Post A')")
    db.exec("INSERT INTO posts (author_id, title) VALUES (1, 'Post B')")
    db.exec("INSERT INTO posts (author_id, title) VALUES (2, 'Post C')")

    db.exec("INSERT INTO comments (post_id, body) VALUES (1, 'c1')")
    db.exec("INSERT INTO comments (post_id, body) VALUES (1, 'c2')")
    db.exec("INSERT INTO comments (post_id, body) VALUES (2, 'c3')")
  end

  describe "lazy loading" do
    it "belongs_to fetches the parent on demand" do
      p = Post.find!(1)
      pp p
      a = p.author
      pp a
      a.should be_a(Author)
      a.not_nil!.name.should eq("Ada")
    end

    it "has_many fetches children on demand" do
      a = Author.find!(1)
      posts = a.posts
      posts.size.should eq(2)
      posts.map(&.title).sort!.should eq(["Post A", "Post B"])
    end

    it "has_one fetches the single child on demand" do
      a = Author.find!(1)
      prof = a.profile
      prof.should be_a(Profile)
      prof.not_nil!.bio.should eq("hello world")

      b = Author.find!(2)
      b.profile.should be_nil
    end
  end

  describe "includes eager loading" do
    it "preloads belongs_to for a collection" do
      posts = Post.rel.order("id ASC").includes(:author).all
      posts.size.should eq(3)

      posts[0].author.not_nil!.name.should eq("Ada")
      posts[1].author.not_nil!.name.should eq("Ada")
      posts[2].author.not_nil!.name.should eq("Lydia")
    end

    it "preloads has_many for a collection" do
      authors = Author.rel.order("id ASC").includes(:posts).all
      authors.size.should eq(2)

      authors[0].posts.size.should eq(2)
      authors[1].posts.size.should eq(1)
    end

    it "preloads has_one for a collection" do
      authors = Author.rel.order("id ASC").includes(:profile).all
      authors.size.should eq(2)

      authors[0].profile.not_nil!.bio.should eq("hello world")
      authors[1].profile.should be_nil
    end

    it "can preload multiple associations at once" do
      posts = Post.rel.order("id ASC").includes(:author, :comments).all
      posts.size.should eq(3)

      posts[0].author.not_nil!.name.should eq("Ada")
      posts[0].comments.size.should eq(2)

      posts[1].author.not_nil!.name.should eq("Ada")
      posts[1].comments.size.should eq(1)

      posts[2].author.not_nil!.name.should eq("Lydia")
      posts[2].comments.size.should eq(0)
    end
  end

  describe "includes reduces query count" do
    it "avoids N+1 when calling association repeatedly" do
      # Lazy path
      CustomOrm::Exec.__spec_reset_query_count
      posts = Post.rel.order("id ASC").all
      posts.each { |p| p.author.try &.name }
      lazy_queries = CustomOrm::Exec.__spec_query_count

      # Eager path
      CustomOrm::Exec.__spec_reset_query_count
      posts2 = Post.rel.order("id ASC").includes(:author).all
      posts2.each { |p| p.author.try &.name }
      eager_queries = CustomOrm::Exec.__spec_query_count

      eager_queries.should be < lazy_queries
    end
  end
end
