module CustomOrm::QueryBuilder
  # Basic SELECT builder
  struct Select
    @table          : String
    @columns        : Array(String)
    @where_clauses  : Array(String)
    @params         : Array(DB::Any)

    def initialize(@table : String, @columns : Array(String) = ["*"] of String)
      @where_clauses = [] of String
      @params = [] of DB::Any
    end

    # Add a WHERE clause with placeholders ($1, ?, etc.)
    def where(cond : String, *vals : DB::Any)
      @where_clauses << cond
      @params.concat(vals)
      self
    end

    # Compose SQL
    def to_sql
      sql = "SELECT #{@columns.join(",")} FROM #{@table}"
      unless @where_clauses.empty?
        sql += " WHERE " + @where_clauses.join(" AND ")
      end
      sql
    end

    # Return bound params
    def bound_params : Array(DB::Any)
      @params
    end
  end

  # INSERT builder
  struct Insert
    @table   : String
    @columns : Array(String)
    @values  : Array(DB::Any)

    def initialize(@table : String, data : Hash(Symbol, DB::Any) | NamedTuple)
      @columns = [] of String
      @values  = [] of DB::Any
      data.each do |col, val|
        @columns << col.to_s
        @values << val
      end
    end

    def to_sql
      cols = @columns.join(", ")
      placeholders = @columns.each_index.map { |i| "$#{i+1}" }.join(", ")
      "INSERT INTO #{@table} (#{cols}) VALUES (#{placeholders}) RETURNING *"
    end

    def bound_params : Array(DB::Any)
      @values
    end
  end

  # UPDATE builder
  struct Update
    @table   : String
    @updates : Array(String)
    @params  : Array(DB::Any)

    def initialize(@table : String, data : Hash(Symbol, DB::Any) | NamedTuple)
      @updates = [] of String
      @params  = [] of DB::Any
      idx = 0
      data.each do |col, val|
        @updates << "#{col} = $#{idx+1}"
        @params << val
        idx += 1
      end
    end

    def where(cond : String, *vals : DB::Any)
      @where = cond
      @params.concat(vals)
      self
    end

    def to_sql
      sql = "UPDATE #{@table} SET " + @updates.join(", ")
      sql += " WHERE #{@where}" if @where
      sql
    end

    def bound_params : Array(DB::Any)
      @params
    end
  end

  # DELETE builder
  struct Delete
    @table  : String
    @where  : String?
    @params : Array(DB::Any)

    def initialize(@table : String)
      @params = [] of DB::Any
    end

    def where(cond : String, *vals : DB::Any)
      @where = cond
      @params.concat(vals)
      self
    end

    def to_sql
      "DELETE FROM #{@table} WHERE #{@where}"
    end

    def bound_params : Array(DB::Any)
      @params
    end
  end

  # Convenience constructors
  def self.select_all(table : String)
    Select.new(table)
  end
  def self.select_by_id(table : String, id : DB::Any)
    select_all(table).where("id = $1", id)
  end

  def self.select_by(table : String, filters : Hash(Symbol, DB::Any) | NamedTuple)
    sel = select_all(table)
    idx = 0
    filters.each do |col, val|
      sel.where("#{col} = $#{idx+1}", val)
      idx += 1
    end
    sel
  end
  
  def self.select_by_statement(table : String, stmt : String, vals : Array(DB::Any) | NamedTuple)
    select_all(table).where(stmt, *vals)
  end

  def self.insert_into(table : String, data : Hash(Symbol, DB::Any) | NamedTuple)
    Insert.new(table, data)
  end

  def self.update(table : String, data : Hash(Symbol, DB::Any) | NamedTuple, id : Int64)
    Update.new(table, data).where("id = $#{data.values.size + 1}", id)
  end

  def self.delete_from(table : String, id : Int64)
    Delete.new(table).where("id = $1", id)
  end
end