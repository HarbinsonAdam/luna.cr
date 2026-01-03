module CustomOrm::QueryBuilder
  # -------------------------
  # Helpers
  # -------------------------
  def self.ph(n : Int32) : String
    "$#{n}"
  end

  def self.append_params!(target : Array(DB::Any), vals : Array(DB::Any))
    target.concat(vals)
  end

  def self.append_params!(target : Array(DB::Any), vals : NamedTuple)
    target.concat(vals.values.to_a.map(&.as(DB::Any)))
  end

  # -------------------------
  # JOIN support
  # -------------------------
  struct JoinClause
    getter type : Symbol        # :inner or :left
    getter table : String
    getter alias_name : String? # <-- rename from `as`
    getter on : String
    getter params : Array(DB::Any)

    def initialize(@type, @table, @on, @alias_name = nil, @params = [] of DB::Any); end

    def to_sql : String
      kind = type == :left ? "LEFT" : "INNER"
      alias_sql = alias_name ? " AS #{alias_name}" : ""
      "#{kind} JOIN #{table}#{alias_sql} ON #{on}"
    end
  end

  # -------------------------
  # SELECT builder
  # -------------------------
  struct Select
    @table          : String
    @columns        : Array(String)
    @where_clauses  : Array(String)
    @params         : Array(DB::Any)
    @joins          : Array(JoinClause)
    @order_by       : Array(String)
    @limit          : Int32?
    @offset         : Int32?

    def initialize(@table : String, @columns : Array(String) = ["*"] of String)
      @where_clauses = [] of String
      @params        = [] of DB::Any
      @joins         = [] of JoinClause
      @order_by      = [] of String
      @limit         = nil
      @offset        = nil
    end

    def select(*cols : String)
      @columns = cols.to_a
      self
    end

    def where(cond : String, *vals : DB::Any)
      @where_clauses << cond
      @params.concat(vals)
      self
    end

    def where_array(cond : String, vals : Array(DB::Any) | NamedTuple)
      @where_clauses << cond
      CustomOrm::QueryBuilder.append_params!(@params, vals)
      self
    end

    def where_hash(filters : Hash(Symbol, DB::Any))
      base = @params.size + 1
      idx  = 0
      filters.each do |col, val|
        @where_clauses << "#{col} = #{CustomOrm::QueryBuilder.ph(base + idx)}"
        @params << val
        idx += 1
      end
      self
    end

    # NamedTuple variant
    def where_hash(filters : NamedTuple)
      base = @params.size + 1
      idx  = 0
      filters.each do |col, val|
        @where_clauses << "#{col} = #{CustomOrm::QueryBuilder.ph(base + idx)}"
        @params << val.as(DB::Any)
        idx += 1
      end
      self
    end

    def add_join(type : Symbol, table : String, on : String, table_alias : String? = nil,
               params : Array(DB::Any) = [] of DB::Any)
      @joins << JoinClause.new(type, table, on, table_alias, params)
      @params.concat(params)
      self
    end

    def inner_join(table : String, on : String, *params : DB::Any, table_alias : String? = nil)
      add_join(:inner, table, on, table_alias, params.to_a)
    end

    def inner_join(table : String, on : String, table_alias : String? = nil)
      add_join(:inner, table, on, table_alias)
      self
    end

    def left_join(table : String, on : String, *params : DB::Any, table_alias : String? = nil)
      add_join(:left, table, on, table_alias, params.to_a)
    end

    def left_join(table : String, on : String, table_alias : String? = nil)
      add_join(:left, table, on, table_alias)
      self
    end

    def order(*cols : String)
      @order_by.concat(cols.to_a)
      self
    end

    def limit(n : Int32)
      @limit = n
      self
    end

    def offset(n : Int32)
      @offset = n
      self
    end

    def where_in(column : String, vals : Array(DB::Any))
      return self if vals.empty?

      base = @params.size + 1
      placeholders = vals.each_index.map { |i| CustomOrm::QueryBuilder.ph(base + i) }.join(", ")
      @where_clauses << "#{column} IN (#{placeholders})"
      @params.concat(vals)
      self
    end

    def to_sql
      sql = "SELECT #{@columns.join(", ")} FROM #{@table}"
      unless @joins.empty?
        sql += " " + @joins.map(&.to_sql).join(" ")
      end
      unless @where_clauses.empty?
        sql += " WHERE " + @where_clauses.join(" AND ")
      end
      unless @order_by.empty?
        sql += " ORDER BY " + @order_by.join(", ")
      end
      sql += " LIMIT #{@limit}" if @limit
      sql += " OFFSET #{@offset}" if @offset
      sql
    end

    def bound_params : Array(DB::Any)
      @params
    end
  end

  # -------------------------
  # INSERT builder
  # -------------------------
  struct Insert
    @table    : String
    @columns  : Array(String)
    @values   : Array(DB::Any)
    @ret_cols : Array(String)?

    def initialize(@table : String, data : Hash(Symbol, DB::Any))
      @columns  = [] of String
      @values   = [] of DB::Any
      @ret_cols = nil
      data.each do |col, val|
        @columns << col.to_s
        @values  << val
      end
    end

    # NamedTuple variant
    def initialize(@table : String, data : NamedTuple)
      @columns  = [] of String
      @values   = [] of DB::Any
      @ret_cols = nil
      data.each do |col, val|
        @columns << col.to_s
        @values  << val.as(DB::Any)
      end
    end

    def returning(*cols : String)
      @ret_cols = cols.to_a
      self
    end

    def to_sql
      cols = @columns.join(", ")
      placeholders = @columns.each_index.map { |i| CustomOrm::QueryBuilder.ph(i + 1) }.join(", ")
      ret = (@ret_cols && !@ret_cols.not_nil!.empty?) ? " RETURNING #{@ret_cols.not_nil!.join(", ")}" : " RETURNING *"
      "INSERT INTO #{@table} (#{cols}) VALUES (#{placeholders})#{ret}"
    end

    def bound_params : Array(DB::Any)
      @values
    end
  end

  # -------------------------
  # UPDATE builder
  # -------------------------
  struct Update
    @table    : String
    @updates  : Array(String)
    @params   : Array(DB::Any)
    @where    : String?
    @ret_cols : Array(String)?

    def initialize(@table : String, data : Hash(Symbol, DB::Any))
      @updates  = [] of String
      @params   = [] of DB::Any
      @where    = nil
      @ret_cols = nil

      base = 1
      data.each do |col, val|
        @updates << "#{col} = #{CustomOrm::QueryBuilder.ph(base)}"
        @params << val
        base += 1
      end
    end

    # NamedTuple variant
    def initialize(@table : String, data : NamedTuple)
      @updates  = [] of String
      @params   = [] of DB::Any
      @where    = nil
      @ret_cols = nil

      base = 1
      data.each do |col, val|
        @updates << "#{col} = #{CustomOrm::QueryBuilder.ph(base)}"
        @params << val.as(DB::Any)
        base += 1
      end
    end

    def where(cond : String, *vals : DB::Any)
      @where = cond
      @params.concat(vals)
      self
    end

    def where_hash(filters : Hash(Symbol, DB::Any))
      base = @params.size + 1
      idx  = 0
      filters.each do |col, val|
        clause = "#{col} = #{CustomOrm::QueryBuilder.ph(base + idx)}"
        @where = @where ? "#{@where} AND #{clause}" : clause
        @params << val
        idx += 1
      end
      self
    end

    def where_hash(filters : NamedTuple)
      base = @params.size + 1
      idx  = 0
      filters.each do |col, val|
        clause = "#{col} = #{CustomOrm::QueryBuilder.ph(base + idx)}"
        @where = @where ? "#{@where} AND #{clause}" : clause
        @params << val.as(DB::Any)
        idx += 1
      end
      self
    end

    def returning(*cols : String)
      @ret_cols = cols.to_a
      self
    end

    def to_sql
      sql = "UPDATE #{@table} SET " + @updates.join(", ")
      sql += " WHERE #{@where}" if @where
      sql += " RETURNING " + (@ret_cols && !@ret_cols.not_nil!.empty? ? @ret_cols.not_nil!.join(", ") : "*")
      sql
    end

    def bound_params : Array(DB::Any)
      @params
    end
  end

  # -------------------------
  # DELETE builder
  # -------------------------
  struct Delete
    @table    : String
    @where    : String?
    @params   : Array(DB::Any)
    @ret_cols : Array(String)?

    def initialize(@table : String)
      @params   = [] of DB::Any
      @where    = nil
      @ret_cols = nil
    end

    def where(cond : String, *vals : DB::Any)
      @where = cond
      @params.concat(vals)
      self
    end

    def where_hash(filters : Hash(Symbol, DB::Any))
      base = @params.size + 1
      idx  = 0
      filters.each do |col, val|
        clause = "#{col} = #{CustomOrm::QueryBuilder.ph(base + idx)}"
        @where = @where ? "#{@where} AND #{clause}" : clause
        @params << val
        idx += 1
      end
      self
    end

    def where_hash(filters : NamedTuple)
      base = @params.size + 1
      idx  = 0
      filters.each do |col, val|
        clause = "#{col} = #{CustomOrm::QueryBuilder.ph(base + idx)}"
        @where = @where ? "#{@where} AND #{clause}" : clause
        @params << val.as(DB::Any)
        idx += 1
      end
      self
    end

    def returning(*cols : String)
      @ret_cols = cols.to_a
      self
    end

    def to_sql
      sql = "DELETE FROM #{@table}"
      sql += " WHERE #{@where}" if @where
      sql += " RETURNING " + (@ret_cols && !@ret_cols.not_nil!.empty? ? @ret_cols.not_nil!.join(", ") : "*")
      sql
    end

    def bound_params : Array(DB::Any)
      @params
    end
  end

  # -------------------------
  # Convenience constructors
  # -------------------------

  def self.select_all(table : String) : Select
    Select.new(table)
  end

  def self.select_by_id(table : String, id : DB::Any, pk : String | Symbol = "id") : Select
    Select.new(table).where("#{pk} = #{ph(1)}", id)
  end

  # filters: Hash
  def self.select_by(table : String, filters : Hash(Symbol, DB::Any)) : Select
    Select.new(table).where_hash(filters)
  end

  # filters: NamedTuple
  def self.select_by(table : String, filters : NamedTuple) : Select
    Select.new(table).where_hash(filters)
  end

  # stmt + params: Array
  def self.select_by_statement(table : String, stmt : String, vals : Array(DB::Any)) : Select
    sel = Select.new(table)
    sel.where_array(stmt, vals)
    sel
  end

  # stmt + params: NamedTuple
  def self.select_by_statement(table : String, stmt : String, vals : NamedTuple) : Select
    sel = Select.new(table)
    sel.where_array(stmt, vals)
    sel
  end

  # INSERT
  def self.insert_into(table : String, data : Hash(Symbol, DB::Any)) : Insert
    Insert.new(table, data)
  end

  def self.insert_into(table : String, data : NamedTuple) : Insert
    Insert.new(table, data)
  end

  # UPDATE (by id)
  def self.update(table : String, data : Hash(Symbol, DB::Any), id : DB::Any, pk : String | Symbol = "id") : Update
    Update.new(table, data).where("#{pk} = #{ph(data.size + 1)}", id)
  end

  def self.update(table : String, data : NamedTuple, id : DB::Any, pk : String | Symbol = "id") : Update
    Update.new(table, data).where("#{pk} = #{ph(data.size + 1)}", id)
  end

  # UPDATE ... WHERE (all combos)
  def self.update_where(table : String, data : Hash(Symbol, DB::Any), filters : Hash(Symbol, DB::Any)) : Update
    Update.new(table, data).where_hash(filters)
  end

  def self.update_where(table : String, data : Hash(Symbol, DB::Any), filters : NamedTuple) : Update
    Update.new(table, data).where_hash(filters)
  end

  def self.update_where(table : String, data : NamedTuple, filters : Hash(Symbol, DB::Any)) : Update
    Update.new(table, data).where_hash(filters)
  end

  def self.update_where(table : String, data : NamedTuple, filters : NamedTuple) : Update
    Update.new(table, data).where_hash(filters)
  end

  # DELETE by id
  def self.delete_from(table : String, id : DB::Any, pk : String | Symbol = "id") : Delete
    Delete.new(table).where("#{pk} = #{ph(1)}", id)
  end

  # DELETE ... WHERE (both input styles)
  def self.delete_where(table : String, filters : Hash(Symbol, DB::Any)) : Delete
    Delete.new(table).where_hash(filters)
  end

  def self.delete_where(table : String, filters : NamedTuple) : Delete
    Delete.new(table).where_hash(filters)
  end
end
