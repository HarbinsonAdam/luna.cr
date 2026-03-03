require "../spec_helper"

enum PublishState
  DRAFT
  REVIEW
  PUBLISHED
  ARCHIVED
end

class Article < Luna::BaseModel
  primary_key id
  attribute title : String
  attribute status : PublishState, default: PublishState::DRAFT

  @[JSON::Field(ignore: true)]
  @[YAML::Field(ignore: true)]
  getter transition_hooks = [] of String

  state_machine status, PublishState, {
    submit:  {from: :draft, to: :review},
    publish: {from: :review, to: :published, before: :before_publish, after: :after_publish},
    archive: {from: [:review, :published], to: :archived},
  }

  def before_publish
    @transition_hooks << "before_publish"
  end

  def after_publish
    @transition_hooks << "after_publish"
  end
end

describe "StateMachine" do
  before_all do
    db = Luna::Setup.db_connections(:default)
    db.exec("DROP TABLE IF EXISTS articles")
    db.exec("CREATE TABLE articles (id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT, status TEXT NOT NULL DEFAULT 'draft')")
  end

  before_each do
    Article.db_connection.exec("DELETE FROM articles")
  end

  it "persists enum-backed state columns and hydrates them back to enum values" do
    article = Article.new(title: "Guide", status: PublishState::DRAFT)
    article.save

    raw_status = Article.db_connection.query_one("SELECT status FROM articles WHERE id = ?", args: [article.id], as: String)
    raw_status.should eq("draft")

    reloaded = Article.find(article.id.not_nil!).not_nil!
    reloaded.status.should eq(PublishState::DRAFT)
    reloaded.status_draft?.should be_true
  end

  it "supports event methods with hooks and bang persistence" do
    article = Article.new(title: "Release Notes", status: PublishState::DRAFT)
    article.save

    article.submit
    article.status.should eq(PublishState::REVIEW)

    article.publish!
    article.status.should eq(PublishState::PUBLISHED)
    article.transition_hooks.should eq(["before_publish", "after_publish"])

    raw_status = Article.db_connection.query_one("SELECT status FROM articles WHERE id = ?", args: [article.id], as: String)
    raw_status.should eq("published")
  end

  it "raises for invalid event-driven transitions" do
    article = Article.new(title: "Bad Path", status: PublishState::DRAFT)
    article.save

    expect_raises(Luna::InvalidStateTransition) do
      article.publish
    end
  end

  it "raises when direct state assignment is not an allowed transition" do
    article = Article.new(title: "Skip Review", status: PublishState::DRAFT)
    article.save
    article = Article.find(article.id.not_nil!).not_nil!
    article.status = PublishState::ARCHIVED
    article.status_changed?.should be_true
    article.status_was.should eq(PublishState::DRAFT)

    expect_raises(Luna::InvalidStateTransition) do
      article.save
    end
  end

  it "allows direct state assignment for transitions configured in the state machine" do
    article = Article.new(title: "Direct But Allowed", status: PublishState::DRAFT)
    article.save
    article = Article.find(article.id.not_nil!).not_nil!
    article.submit!
    article = Article.find(article.id.not_nil!).not_nil!
    article.status = PublishState::PUBLISHED
    article.save

    raw_status = Article.db_connection.query_one("SELECT status FROM articles WHERE id = ?", args: [article.id], as: String)
    raw_status.should eq("published")
  end
end
