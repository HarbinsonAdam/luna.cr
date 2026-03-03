require "../spec_helper"

# ----------------------------------------
# Test models
# ----------------------------------------

class Author < Luna::BaseModel
  primary_key id
  attribute name : String

  has_many posts, klass: Post, foreign_key: author_id
  has_one profile, klass: Profile, foreign_key: author_id
end

class Profile < Luna::BaseModel
  primary_key id
  attribute author_id : Int64
  attribute bio : String

  belongs_to author, klass: Author, foreign_key: author_id
end

class Post < Luna::BaseModel
  primary_key id
  attribute author_id : Int64?
  attribute title : String

  belongs_to author, klass: Author, foreign_key: author_id
  has_many comments, klass: Comment, foreign_key: post_id
end

class Comment < Luna::BaseModel
  primary_key id
  attribute post_id : Int64
  attribute body : String
end

# ----------------------------------------
# Spec-only query counter (instrument Exec)
# ----------------------------------------
module Luna::Exec
  @@__spec_query_count : Int32 = 0

  def self.__spec_reset_query_count
    @@__spec_query_count = 0
  end

  def self.__spec_query_count : Int32
    @@__spec_query_count
  end

  def self.query_all(db : DB::Database, sql : String, params : Array(DB::Any),
                     dialect : Luna::SQL::Dialect, model_name : String? = nil, operation : String? = nil,
                     &block : DB::ResultSet ->)
    @@__spec_query_count += 1
    previous_def(db, sql, params, dialect, model_name, operation) do |rs|
      yield rs
    end
  end

  def self.exec(db : DB::Database, sql : String, params : Array(DB::Any),
                dialect : Luna::SQL::Dialect, model_name : String? = nil, operation : String? = nil)
    @@__spec_query_count += 1
    previous_def(db, sql, params, dialect, model_name, operation)
  end

  def self.query_one(db : DB::Database, sql : String, params : Array(DB::Any),
                     dialect : Luna::SQL::Dialect, type : T.class, model_name : String? = nil,
                     operation : String? = nil) : T forall T
    @@__spec_query_count += 1
    previous_def(db, sql, params, dialect, type, model_name, operation)
  end
end

# ----------------------------------------
# Specs
# ----------------------------------------

describe "Associations" do
  before_each do
    db = Luna::Setup.db_connections(:default)
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
      a = p.author
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
      Luna::Exec.__spec_reset_query_count
      posts = Post.rel.order("id ASC").all
      posts.each { |p| p.author.try &.name }
      lazy_queries = Luna::Exec.__spec_query_count

      # Eager path
      Luna::Exec.__spec_reset_query_count
      posts2 = Post.rel.order("id ASC").includes(:author).all
      posts2.each { |p| p.author.try &.name }
      eager_queries = Luna::Exec.__spec_query_count

      eager_queries.should be < lazy_queries
    end
  end
end

describe "Associations (nested includes)" do
  before_each do
    db = Luna::Setup.db_connections(:default)

    # IMPORTANT: drop+create each time so AUTOINCREMENT ids are deterministic
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

  # ------------------------
  # Lazy sanity checks
  # ------------------------
  describe "lazy loading sanity" do
    it "still lazy-loads nested associations (posts -> comments)" do
      a = Author.find!(1)
      a.posts.size.should eq(2)

      first_post = a.posts.find { |p| p.title == "Post A" }
      first_post.should_not be_nil
      first_post.not_nil!.comments.size.should eq(2)
    end
  end

  # ------------------------
  # Nested includes
  # ------------------------
  describe "nested includes eager loading" do
    it "supports includes(posts: :comments) from parent -> children -> grandchildren" do
      authors = Author.rel.order("id ASC").includes(posts: :comments).all
      authors.size.should eq(2)

      a1 = authors[0]
      a2 = authors[1]

      a1.name.should eq("Ada")
      a1.posts.size.should eq(2)

      # Post A has 2 comments, Post B has 1
      by_title = a1.posts.to_h { |p| {p.title, p} }
      by_title["Post A"].comments.size.should eq(2)
      by_title["Post B"].comments.size.should eq(1)

      a2.name.should eq("Lydia")
      a2.posts.size.should eq(1)
      a2.posts[0].title.should eq("Post C")
      a2.posts[0].comments.size.should eq(0)
    end

    it "supports includes(author: :profile) from child -> parent -> parent's child" do
      posts = Post.rel.order("id ASC").includes(author: :profile).all
      posts.size.should eq(3)

      p1 = posts[0]
      p2 = posts[1]
      p3 = posts[2]

      p1.author.not_nil!.name.should eq("Ada")
      p1.author.not_nil!.profile.not_nil!.bio.should eq("hello world")

      p2.author.not_nil!.name.should eq("Ada")
      p2.author.not_nil!.profile.not_nil!.bio.should eq("hello world")

      p3.author.not_nil!.name.should eq("Lydia")
      p3.author.not_nil!.profile.should be_nil
    end

    it "supports deep mixed includes: posts include author and comments" do
      posts = Post.rel.order("id ASC").includes(:author, :comments).all
      posts.size.should eq(3)

      posts[0].author.not_nil!.name.should eq("Ada")
      posts[0].comments.size.should eq(2)

      posts[1].author.not_nil!.name.should eq("Ada")
      posts[1].comments.size.should eq(1)

      posts[2].author.not_nil!.name.should eq("Lydia")
      posts[2].comments.size.should eq(0)
    end

    it "supports deep tree: author includes posts, and posts include comments" do
      # Equivalent shapes you may support:
      # - includes(posts: :comments)
      # - includes(posts: [:comments])
      # - includes(posts: { comments: [] of Symbol })
      authors = Author.rel.order("id ASC").includes(posts: [:comments]).all
      authors.size.should eq(2)

      a1 = authors[0]
      a1.posts.size.should eq(2)
      a1.posts.sum { |p| p.comments.size }.should eq(3) # 2 + 1

      a2 = authors[1]
      a2.posts.size.should eq(1)
      a2.posts[0].comments.size.should eq(0)
    end
  end

  # ------------------------
  # Query-count: nested N+1
  # ------------------------
  describe "nested includes reduces query count" do
    it "avoids N+1 for (authors -> posts -> comments)" do
      # Lazy path (expect: 1 for authors + per-author posts + per-post comments)
      Luna::Exec.__spec_reset_query_count
      authors = Author.rel.order("id ASC").all
      authors.each do |a|
        a.posts.each do |p|
          p.comments.size
        end
      end
      lazy = Luna::Exec.__spec_query_count
      
      # Eager path (expect: 1 for authors + 1 for posts + 1 for comments)
      Luna::Exec.__spec_reset_query_count
      authors2 = Author.rel.order("id ASC").includes(posts: :comments).all
      authors2.each do |a|
        a.posts.each do |p|
          p.comments.size
        end
      end
      eager = Luna::Exec.__spec_query_count

      eager.should be < lazy
      # A sanity bound that’s stable for this seed set if eager loading is correct:
      # authors, posts, comments = 3 queries (+ maybe ordering variations)
      eager.should be <= 4
    end

    it "avoids N+1 for (posts -> author -> profile)" do
      # Lazy: 1 (posts) + per-post author + per-author profile (may re-fetch author)
      Luna::Exec.__spec_reset_query_count
      posts = Post.rel.order("id ASC").all
      posts.each do |p|
        p.author.try do |a|
          a.profile.try &.bio
        end
      end
      lazy = Luna::Exec.__spec_query_count

      # Eager: 1 (posts) + 1 (authors) + 1 (profiles)
      Luna::Exec.__spec_reset_query_count
      posts2 = Post.rel.order("id ASC").includes(author: :profile).all
      posts2.each do |p|
        p.author.try do |a|
          a.profile.try &.bio
        end
      end
      eager = Luna::Exec.__spec_query_count

      eager.should be < lazy
      eager.should be <= 4
    end
  end
end
