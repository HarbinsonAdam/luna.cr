module CustomOrm
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
end
