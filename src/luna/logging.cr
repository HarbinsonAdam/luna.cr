require "db"
require "log"

module Luna
  module Logging
    @@query_logging_enabled = false
    @@query_logger = Log.for("luna.query")

    def self.query_logging_enabled? : Bool
      @@query_logging_enabled
    end

    def self.enable_query_logging
      @@query_logging_enabled = true
    end

    def self.disable_query_logging
      @@query_logging_enabled = false
    end

    def self.log_query(sql : String, params : Array(DB::Any), elapsed_ms : Float64,
                       model_name : String? = nil, operation : String? = nil)
      return unless @@query_logging_enabled

      label = query_label(sql, model_name, operation)
      @@query_logger.info do
        "#{label} (#{format_ms(elapsed_ms)}ms) #{sql} -- params: #{params.inspect}"
      end
    end

    def self.log_transaction(event : String, elapsed_ms : Float64 = 0.0)
      return unless @@query_logging_enabled
      @@query_logger.info { "(#{format_ms(elapsed_ms)}ms) #{event}" }
    end

    private def self.query_label(sql : String, model_name : String?, operation : String?) : String
      return "SQL" unless model_name

      action = operation || infer_action(sql)
      "#{model_name} #{action}"
    end

    private def self.infer_action(sql : String) : String
      statement = sql.lstrip.split(/\s+/, 2).first?.to_s.upcase
      case statement
      when "SELECT" then "Load"
      when "INSERT" then "Create"
      when "UPDATE" then "Update"
      when "DELETE" then "Destroy"
      else               "SQL"
      end
    end

    private def self.format_ms(value : Float64) : String
      "%.1f" % value
    end
  end
end
