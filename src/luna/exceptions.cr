module Luna
  class ModelAlreadyFetchedException < Exception
    def initialize(@model : String)
      super("Model #{@model} has already been fetched.")
    end
  end

  class RecordNotSavedError < Exception
    def initialize(@model : String)
      super("Model #{@model} has not been saved.")
    end
  end

  class RecordNotValidError < Exception
    def initialize(@errors : Array(ActiveModel::Error))
      super("Record is invalid, #{@errors}")
    end
  end

  class RecordNotFound < Exception
    def initialize(@message : String)
      super(@message)
    end
  end

  class InvalidStateTransition < Exception
    def initialize(model : String, column : Symbol, from_state : Symbol, to_state : Symbol, event : Symbol? = nil)
      message = if event
        "Invalid state transition on #{model}.#{column}: #{from_state} -> #{to_state} (event: #{event})"
      else
        "Invalid state transition on #{model}.#{column}: #{from_state} -> #{to_state}"
      end
      super(message)
    end
  end

  class Rollback < Exception
  end
end
