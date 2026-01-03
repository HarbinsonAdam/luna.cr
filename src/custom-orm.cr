struct UUID
  def self.new(pull : JSON::PullParser)
    string = pull.read_string
    UUID.new(string)
  end

  def to_json(json : JSON::Builder) : Nil
    json.string(self)
  end

  def self.from_json_object_key?(key : String) : self
    UUID.new(key)
  end

  def to_json_object_key : String
    to_s
  end
end

require "active-model"
require "./custom_orm/setup"
require "./custom_orm/exceptions"
require "./custom_orm/query_builder"
require "./custom_orm/relation"
require "./custom_orm/associations"
require "./custom_orm/base_model"
require "./custom_orm/migrations/*"