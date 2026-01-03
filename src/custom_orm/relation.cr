# src/custom_orm/relation.cr
require "./exec"
require "./query_builder"
require "./include_paths"

module CustomOrm
  class Relation(T)
    @table : String
    @model : T.class
    @query : CustomOrm::QueryBuilder::Select
    @includes_paths : Array(Array(Symbol)) = [] of Array(Symbol)

    def initialize
      @model = T
      @table = T.table_name
      @query = CustomOrm::QueryBuilder.select_all(@table)
    end

    # WHERE variants
    def where(cond : String, *params : DB::Any)
      @query.where(cond, *params)
      self
    end

    def where(filters : Hash(Symbol, DB::Any))
      @query = CustomOrm::QueryBuilder.select_by(@table, filters)
      self
    end

    def where(filters : NamedTuple)
      @query = CustomOrm::QueryBuilder.select_by(@table, filters)
      self
    end

    def where_in(column : String, vals : Array(DB::Any))
      @query.where_in(column, vals)
      self
    end

    # Join DSL
    def inner_join(table : String, on : String, *params : DB::Any, table_alias : String? = nil)
      @query.inner_join(table, on, *params, table_alias: table_alias)
      self
    end

    def inner_join(table : String, on : String, table_alias : String? = nil)
      @query.inner_join(table, on, table_alias)
      self
    end

    def left_join(table : String, on : String, *params : DB::Any, table_alias : String? = nil)
      @query.left_join(table, on, *params, table_alias: table_alias)
      self
    end

    def left_join(table : String, on : String, table_alias : String? = nil)
      @query.left_join(table, on, table_alias)
      self
    end

    # Projection / order / paging (proxy)
    def select(*cols : String)
      @query.select(*cols); self
    end

    def order(*cols : String)
      @query.order(*cols); self
    end

    def limit(n : Int32)
      @query.limit(n); self
    end

    def offset(n : Int32)
      @query.offset(n); self
    end

    def includes(*incs : Symbol)
      @includes_paths.concat(CustomOrm::IncludePaths.build(*incs))
      self
    end

    # keywords only (THIS fixes includes(posts: :comments))
    def includes(**nested)
      @includes_paths.concat(CustomOrm::IncludePaths.build(**nested))
      self
    end

    # both
    def includes(*incs : Symbol, **nested)
      @includes_paths.concat(CustomOrm::IncludePaths.build(*incs, **nested))
      self
    end

    def to_sql
      @query.to_sql
    end

    def all : Array(T)
      db = @model.db_connection
      dialect = @model.db_dialect
      records = [] of T

      CustomOrm::Exec.query_all(db, to_sql, @query.bound_params, dialect) do |rs|
        while rs.move_next
          records << @model.from_db_rs(rs)
        end
      end

      unless @includes_paths.empty?
        @model.__eager_load_paths(records, @includes_paths)
      end

      records
    end

    def first : T?
      limit(1)
      all.first?
    end

    # ------------------------
    # Aggregates & helpers
    # ------------------------
    private def aggregate_sql(expr : String)
      q = @query # struct copy (no side effects)
      q.select(expr)
      q.to_sql
    end

    def count(column : String = "*", distinct : Bool = false) : Int64
      expr    = distinct && column != "*" ? "COUNT(DISTINCT #{column})" : "COUNT(#{column})"
      db      = @model.db_connection
      dialect = @model.db_dialect
      CustomOrm::Exec.query_one(db, aggregate_sql(expr), @query.bound_params, dialect, as: Int64)
    end

    def exists? : Bool
      count > 0
    end

    # Single-column pluck with static type
    def pluck(column : String, as : TVal.class) : Array(TVal) forall TVal
      q = @query
      q.select(column)
      db = @model.db_connection
      dialect = @model.db_dialect
      out = [] of TVal
      CustomOrm::Exec.query_all(db, q.to_sql, q.bound_params, dialect) do |rs|
        while rs.move_next
          out << rs.read(TVal)
        end
      end
      out
    end

    # Numeric aggregates (typed)
    def sum(column : String, as : TNum.class) : TNum? forall TNum
      db = @model.db_connection; dialect = @model.db_dialect
      CustomOrm::Exec.query_one(db, aggregate_sql("SUM(#{column})"), @query.bound_params, dialect, as: TNum)
    rescue DB::NoResultsError
      nil
    end

    def avg(column : String, as : TNum.class) : TNum? forall TNum
      db = @model.db_connection; dialect = @model.db_dialect
      CustomOrm::Exec.query_one(db, aggregate_sql("AVG(#{column})"), @query.bound_params, dialect, as: TNum)
    rescue DB::NoResultsError
      nil
    end

    def min(column : String, as : TVal.class) : TVal? forall TVal
      db = @model.db_connection; dialect = @model.db_dialect
      CustomOrm::Exec.query_one(db, aggregate_sql("MIN(#{column})"), @query.bound_params, dialect, as: TVal)
    rescue DB::NoResultsError
      nil
    end

    def max(column : String, as : TVal.class) : TVal? forall TVal
      db = @model.db_connection; dialect = @model.db_dialect
      CustomOrm::Exec.query_one(db, aggregate_sql("MAX(#{column})"), @query.bound_params, dialect, as: TVal)
    rescue DB::NoResultsError
      nil
    end
  end
end
