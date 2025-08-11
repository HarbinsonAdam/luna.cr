module CustomOrm
  class Relation(T)
    @table : String
    @model : T.class
    @query : CustomOrm::QueryBuilder::Select

    def initialize
      @model      = T
      @table      = T.table_name
      @query      = CustomOrm::QueryBuilder.select_all(@table)
    end

    def where(cond : String, *params : DB::Any)
      @query.where(cond, *params)
      self
    end

    def where(filters : Hash(Symbol, DB::Any))
      @query = CustomOrm::QueryBuilder.select_by(@table, filters)
      self
    end

    def where(filters)
      @query = CustomOrm::QueryBuilder.select_by(@table, filters.to_h)
      self
    end

    def to_sql
      @query.to_sql
    end

    def all : Array(T)
      db     = @model.db_connection
      results = [] of T
      db.query(to_sql, args: @query.bound_params) do |rs|
        rs.each do
          # Convert each row to the model instance
          results << @model.from_db_rs(rs)
        end
      end
      results
    end

    def first : T?
      all.first
    end
  end
end
