abstract class Luna::BaseModel < ActiveModel::Model
  include ActiveModel::Callbacks
  include ActiveModel::Validation
  include Luna::Associations

  # inside Luna::BaseModel

  @[JSON::Field(ignore: true)]
  @__preloaded_one : Hash(Symbol, Luna::BaseModel?) = Hash(Symbol, Luna::BaseModel?).new

  @[JSON::Field(ignore: true)]
  @__preloaded_many : Hash(Symbol, Array(Luna::BaseModel)) = Hash(Symbol, Array(Luna::BaseModel)).new

  @@connection_name : Symbol = :default
  @@primary_key_field : String = "id"

  setter fetched : Bool = false

  # --- Macros ---
  macro connection(name)
    @@connection_name = {{name}}
  end

  macro primary_key(field)
    attribute {{field.id}} : Int64
    @@primary_key_field = {{field.id.stringify}}

    def primary_key
      {{field.id}}
    end
  end

  # --- Class helpers ---
  def self.db_connection
    Luna::Setup.db_connections(@@connection_name)
  end

  def self.primary_key_field
    @@primary_key_field
  end

  def self.all : Array(self)
    Relation(self).new.all
  end

  def self.find(id : Int64) : self?
    Relation(self).new.where("#{primary_key_field} = $1", id).first
  end

  def self.find!(id : Int64) : self
    find(id) || raise(RecordNotFound.new("#{self.name} with #{primary_key_field}=#{id} not found"))
  end

  def self.find_by(filters : Hash(Symbol, DB::Any) | NamedTuple) : self?
    Relation(self).new.where(filters).first
  end

  def self.find_by!(filters : Hash(Symbol, DB::Any) | NamedTuple) : self
    find_by(filters) || raise(RecordNotFound.new("#{self.name} not found for #{filters}"))
  end

  def self.where(cond : String, *params : DB::Any) : Array(self)
    Relation(self).new.where(cond, *params).all
  end

  def self.where(filters : Hash(Symbol, DB::Any) | NamedTuple) : Array(self)
    Relation(self).new.where(filters).all
  end

  def self.__eager_load_paths(records : Array(self), paths : Array(Array(Symbol)))
    # overwritten by Associations.inherited macro
  end


  # --- Instance persistence ---
  def self.connection_name : Symbol
    @@connection_name
  end

  def self.db_dialect : Luna::SQL::Dialect
    Luna::Setup.dialect(@@connection_name)
  end

  private def dialect_supports_returning? : Bool
    case self.class.db_dialect
    when Luna::SQL::Dialect::Pg     then true
    when Luna::SQL::Dialect::Sqlite then Luna::SQL.sqlite_supports_returning?(self.class.db_connection)
    else false
    end
  end

  private def strip_returning(sql : String) : String
    # naive but effective: remove trailing " RETURNING ..."
    sql.sub(/\s+RETURNING\s+.+\z/, "")
  end

  def save
    run_save_callbacks do
      if @fetched
        run_update_callbacks do
          valid?
          invalid_fields = changed_attributes.keys.select { |k| errors.any? { |e| e.field.to_s == k.to_s } }
          raise RecordNotValidError.new(errors) unless invalid_fields.empty?

          db_data = to_db_hash(changed_attributes.compact!)
          upd     = QueryBuilder.update(table_name, db_data, primary_key)
          sql     = upd.to_sql
          params  = upd.bound_params

          if dialect_supports_returning?
            Luna::Exec.query_all(self.class.db_connection, sql, params, self.class.db_dialect) do |rs|
              if rs.move_next
                assign_attributes_from_json(self.class.from_db_rs(rs).to_json)
              end
            end
          else
            Luna::Exec.exec(self.class.db_connection, strip_returning(sql), params, self.class.db_dialect)
          end
        end
      else
        run_create_callbacks do
          valid?
          invalid_fields = attributes.compact!.keys.select { |k| errors.any? { |e| e.field.to_s == k.to_s } }
          raise RecordNotValidError.new(errors) unless invalid_fields.empty?

          db_data = to_db_hash(attributes.compact!)
          ins     = QueryBuilder.insert_into(table_name, db_data)
          sql     = ins.to_sql
          params  = ins.bound_params

          if dialect_supports_returning?
            Luna::Exec.query_all(self.class.db_connection, sql, params, self.class.db_dialect) do |rs|
              if rs.move_next
                assign_attributes_from_json(self.class.from_db_rs(rs).to_json)
              end
            end
          else
            Luna::Exec.exec(self.class.db_connection, strip_returning(sql), params, self.class.db_dialect)
          end

          @fetched = true
        end
      end
    end
  end

  def update
    return unless @fetched
    run_save_callbacks do
      run_update_callbacks do
        valid?
        invalid_fields = changed_attributes.keys.select { |k| errors.any? { |e| e.field.to_s == k.to_s } }
        raise RecordNotValidError.new(errors) unless invalid_fields.empty?

        db_data = to_db_hash(changed_attributes.compact!)
        upd     = QueryBuilder.update(table_name, db_data, primary_key)
        sql     = upd.to_sql
        params  = upd.bound_params

        if dialect_supports_returning?
          Luna::Exec.query_all(self.class.db_connection, sql, params, self.class.db_dialect) do |rs|
            if rs.move_next
              assign_attributes_from_json(self.class.from_db_rs(rs).to_json)
            end
          end
        else
          Luna::Exec.exec(self.class.db_connection, strip_returning(sql), params, self.class.db_dialect)
        end
      end
    end
  end

  def destroy
    return unless @fetched
    run_destroy_callbacks do
      del = QueryBuilder.delete_from(table_name, primary_key)
      sql = del.to_sql
      params = del.bound_params

      if dialect_supports_returning?
        Luna::Exec.query_all(self.class.db_connection, sql, params, self.class.db_dialect) do |rs|
          if rs.move_next
            assign_attributes_from_json(self.class.from_db_rs(rs).to_json)
          end
        end
      else
        Luna::Exec.exec(self.class.db_connection, strip_returning(sql), params, self.class.db_dialect)
      end
    end
  end

  # --- Row mapping macro hook ---
  macro __customize_orm__
    def self.from_db_rs(rs : DB::ResultSet) : self
      stuff = new
      rs.each_column do |column_name|
        {% for key, opts in FIELDS %}
          if {{key.stringify}} == column_name
            val = rs.read({{opts[:klass]}})
            stuff.{{key}} = val
          end
        {% end %}
      end
      stuff.fetched = true
      stuff.clear_changes_information # Ensure original data is not overwritten on update
      stuff
    end
  end

  def self.rel
    Relation(self).new
  end

  # Aggregates & helpers (class level)
  def self.count(column : String = "*", distinct : Bool = false) : Int64
    rel.count(column, distinct)
  end

  def self.exists?(filters : Hash(Symbol, DB::Any) | NamedTuple | Nil = nil) : Bool
    r = filters ? rel.where(filters) : rel
    r.exists?
  end

  def self.pluck(column : String, as : T.class) : Array(T) forall T
    rel.pluck(column, as: T)
  end

  def self.sum(column : String, as : T.class) : T? forall T
    rel.sum(column, as: T)
  end

  def self.avg(column : String, as : T.class) : T? forall T
    rel.avg(column, as: T)
  end

  def self.min(column : String, as : T.class) : T? forall T
    rel.min(column, as: T)
  end

  def self.max(column : String, as : T.class) : T? forall T
    rel.max(column, as: T)
  end

  # Transactions
  def self.transaction(&block)
    db_connection.transaction do |tx|
      Luna::Context.with_connection(tx.connection) { yield }
    end
  end

  # --- Table name helpers ---
  def self.table_name
    table_name_for_class(self)
  end

  def table_name
    table_name_for_class(self.class)
  end

  private def table_name_for_class(klass)
    name_parts = klass.name.split("::")
    table_name = name_parts.size == 3 ? name_parts[1].underscore : name_parts.last.underscore
    "#{table_name}s"
  end

  private def self.table_name_for_class(klass)
    name_parts = klass.name.split("::")
    table_name = name_parts.size == 3 ? name_parts[1].underscore : name_parts.last.underscore
    "#{table_name}s"
  end

  private def to_db_hash(attrs : Hash(Symbol, _)) : Hash(Symbol, DB::Any)
    out = Hash(Symbol, DB::Any).new
    attrs.each do |key, value|
      out[key] = to_db_value(value)
    end
    out
  end

  private def to_db_value(value) : DB::Any
    case value
    when JSON::Any
      # store JSON as text in the DB (for json/jsonb columns)
      value.to_json
    when String, Int32, Int64, Bool, Float32, Float64, Time, Nil, Slice(UInt8)
      value
    else
      # You can adjust this if you later add more custom types
      raise "Unsupported DB value type: #{value.class}"
    end
  end

  def read_attribute(key : String) : DB::Any
    attributes.each do |k, v|
      return v.as(DB::Any) if k.to_s == key
    end
    raise KeyError.new("Unknown attribute #{key}")
  end

  def read_attribute?(key : String) : DB::Any?
    attributes.each do |k, v|
      return v.as(DB::Any) if k.to_s == key
    end
    nil
  end

  macro __define_preload_setter__
    def set_preloaded(name : Symbol, value)
      case name
      {% for ivar in @type.instance_vars %}
        {% if ivar.name.starts_with?("__preloaded_") %}
          when {{ ivar.name["__preloaded_".size..-1].id.symbolize }}
            @{{ ivar.name.id }} = value.as({{ ivar.type }})
        {% end %}
      {% end %}
      else
        # ignore unknown associations
      end
    end
  end

  macro inherited
    macro finished
      __define_preload_setter__
    end
  end
end
