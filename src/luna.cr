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
require "./luna/setup"
require "./luna/exceptions"
require "./luna/sti"
require "./luna/query_builder"
require "./luna/relation"
require "./luna/associations"
require "./luna/base_model"
require "./luna/transaction"
require "./luna/migrations/*"
