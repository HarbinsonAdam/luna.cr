abstract class CustomOrm::BaseModel < ActiveModel::Model
  include ActiveModel::Callbacks
  include ActiveModel::Validation

  @@connection_name = :default
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
    CustomOrm::Setup.db_connections(@@connection_name)
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

  # --- Instance persistence ---
  def self.connection_name : Symbol
    @@connection_name
  end

  def self.db_dialect : CustomOrm::SQL::Dialect
    CustomOrm::Setup.dialect(@@connection_name)
  end

  private def dialect_supports_returning? : Bool
    case self.class.db_dialect
    when CustomOrm::SQL::Dialect::Pg     then true
    when CustomOrm::SQL::Dialect::Sqlite then CustomOrm::SQL.sqlite_supports_returning?(self.class.db_connection)
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

          upd = QueryBuilder.update(table_name, changed_attributes.compact!, primary_key)
          sql = upd.to_sql
          params = upd.bound_params

          if dialect_supports_returning?
            CustomOrm::Exec.query_all(self.class.db_connection, sql, params, self.class.db_dialect) do |rs|
              if rs.move_next
                assign_attributes_from_json(self.class.from_db_rs(rs).to_json)
              end
            end
          else
            CustomOrm::Exec.exec(self.class.db_connection, strip_returning(sql), params, self.class.db_dialect)
          end
        end
      else
        run_create_callbacks do
          valid?
          invalid_fields = attributes.compact!.keys.select { |k| errors.any? { |e| e.field.to_s == k.to_s } }
          raise RecordNotValidError.new(errors) unless invalid_fields.empty?

          ins = QueryBuilder.insert_into(table_name, attributes.compact!)
          sql = ins.to_sql
          params = ins.bound_params

          if dialect_supports_returning?
            CustomOrm::Exec.query_all(self.class.db_connection, sql, params, self.class.db_dialect) do |rs|
              if rs.move_next
                assign_attributes_from_json(self.class.from_db_rs(rs).to_json)
              end
            end
          else
            CustomOrm::Exec.exec(self.class.db_connection, strip_returning(sql), params, self.class.db_dialect)
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

        upd = QueryBuilder.update(table_name, changed_attributes.compact!, primary_key)
        sql = upd.to_sql
        params = upd.bound_params

        if dialect_supports_returning?
          CustomOrm::Exec.query_all(self.class.db_connection, sql, params, self.class.db_dialect) do |rs|
            if rs.move_next
              assign_attributes_from_json(self.class.from_db_rs(rs).to_json)
            end
          end
        else
          CustomOrm::Exec.exec(self.class.db_connection, strip_returning(sql), params, self.class.db_dialect)
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
        CustomOrm::Exec.query_all(self.class.db_connection, sql, params, self.class.db_dialect) do |rs|
          if rs.move_next
            assign_attributes_from_json(self.class.from_db_rs(rs).to_json)
          end
        end
      else
        CustomOrm::Exec.exec(self.class.db_connection, strip_returning(sql), params, self.class.db_dialect)
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
      CustomOrm::Context.with_connection(tx.connection) { yield }
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
end
