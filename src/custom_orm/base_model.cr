abstract class CustomOrm::BaseModel < ActiveModel::Model
  include ActiveModel::Callbacks
  include ActiveModel::Validation

  @@connection_name = :default
  setter fetched : Bool = false
  @@primary_key_field : String = "id"
      # Macro to set the connection name at runtime
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
      # Runtime accessor for the DB connection
  def self.db_connection
    CustomOrm::Setup.db_connections(@@connection_name)
  end

  def self.primary_key_field
    @@primary_key_field
  end

  def self.all : Array(self)
    Relation(self).new.all
  end

  def self.find(id : Int32) : self?
    Relation(self).new.where("#{primary_key_field} = $1", id).first
  end

  def self.find!(id : Int32) : self
    find(id) || raise(RecordNotFound.new("#{__type_name} with #{primary_key_field}=#{id} not found"))
  end

  def self.find_by(filters : Hash(Symbol, DB::Any) | NamedTuple) : self?
    Relation(self).new.where(filters).first
  end

  def self.find_by!(filters : Hash(Symbol, DB::Any)) : self
    find_by(filters) || raise(RecordNotFound.new("#{__type_name} not found for #{filters}"))
  end

  def self.where(cond : String, *params : DB::Any) : Array(self)
    Relation(self).new.where(cond, *params).all
  end

  def self.where(filters : Hash(Symbol, DB::Any)) : Array(self)
    Relation(self).new.where(filters).all
  end

  def save
    run_save_callbacks do
      if @fetched
        run_update_callbacks do
          valid?
          invalid_fields = changed_attributes.keys.select { |key| errors.any? { |error| error.field.to_s == key.to_s } }
          raise RecordNotValidError.new(errors) unless invalid_fields.empty?
          upd = QueryBuilder.update(table_name, changed_attributes.compact!, primary_key)
          res = self.class.db_connection.exec(upd.to_sql, args: upd.bound_params)
        end
      else
        run_create_callbacks do
          valid?
          invalid_fields = attributes.compact!.keys.select { |key| errors.any? { |error| error.field.to_s == key.to_s } }
          raise RecordNotValidError.new(errors) unless invalid_fields.empty?
          ins = QueryBuilder.insert_into(table_name, attributes.compact!)
          self.class.db_connection.query_one(ins.to_sql, args: ins.bound_params) { |rs| assign_attributes_from_json(self.class.from_db_rs(rs).to_json) }
        end
      end
    end
  end

  def update
    if @fetched
      run_save_callbacks do
        run_update_callbacks do
          valid?
          invalid_fields = changed_attributes.keys.select { |key| errors.any? { |error| error.field.to_s == key.to_s } }
          raise RecordNotValidError.new(errors) unless invalid_fields.empty?
          upd = QueryBuilder.update(table_name, changed_attributes.compact!, primary_key)
          res = self.class.db_connection.exec(upd.to_sql, args: upd.bound_params)
        end
      end
    end
  end

  def destroy
    if @fetched
      run_destroy_callbacks do
        del = QueryBuilder.delete_from(table_name, primary_key)
        res = self.class.db_connection.exec(del.to_sql, args: del.bound_params)
      end
    end
  end

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

  def self.table_name
    table_name_for_class(self)
  end

  def table_name
    table_name_for_class(self.class)
  end

  private def table_name_for_class(klass)
    name_parts = klass.name.split("::")

    # If there are three namespaces, use the second component as the table name
    if name_parts.size == 3
      table_name = name_parts[1].underscore
    else
      # Otherwise, use the last component
      table_name = name_parts.last.underscore
    end

    "#{table_name}s"
  end

  private def self.table_name_for_class(klass)
    name_parts = klass.name.split("::")

    # If there are three namespaces, use the second component as the table name
    if name_parts.size == 3
      table_name = name_parts[1].underscore
    else
      # Otherwise, use the last component
      table_name = name_parts.last.underscore
    end

    "#{table_name}s"
  end
end
