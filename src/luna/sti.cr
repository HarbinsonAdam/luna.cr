module Luna
  module Sti
    @@mappings = Hash(String, Hash(String, Luna::BaseModel.class)).new do |h, k|
      h[k] = Hash(String, Luna::BaseModel.class).new
    end

    def self.register(parent : Luna::BaseModel.class, type_value : String, klass : Luna::BaseModel.class) : Nil
      key = parent.name.ends_with?('+') ? parent.name[0...-1] : parent.name
      @@mappings[key][type_value] = klass
    end

    def self.lookup(parent : Luna::BaseModel.class, type_value : String) : Luna::BaseModel.class | Nil
      key = parent.name.ends_with?('+') ? parent.name[0...-1] : parent.name
      @@mappings[key]?.try &.[type_value]?
    end

    macro sti(column)
      attribute {{column.id}} : String?
      STI_COLUMN = {{column.id.stringify}}

      def self.sti_column_name : String?
        STI_COLUMN
      end

      def self.sti_persisted_type_value : String?
        self.name.split("::").last
      end

      def self.from_db_row(rs : DB::ResultSet) : self
        row = __read_row_hash(rs)
        type_value = row[STI_COLUMN]?.try { |v| self.__db_any_to_sti_type(v) }
        if value = type_value
          if klass = __sti_class_for(value)
            return klass.__from_db_hash(row).as(self)
          end
        end

        __from_db_hash(row)
      end
    end

    macro sti_type(type_value)
      LUNA_STI_TYPE = ({{type_value}}).to_s

      def self.sti_column_name : String?
        ::{{@type.superclass}}.sti_column_name
      end

      def self.sti_scope_type_value : String?
        Luna::Sti.register(::{{@type.superclass}}, LUNA_STI_TYPE, self)
        LUNA_STI_TYPE
      end

      def self.sti_persisted_type_value : String?
        Luna::Sti.register(::{{@type.superclass}}, LUNA_STI_TYPE, self)
        LUNA_STI_TYPE
      end

      def self.table_name
        ::{{@type.superclass}}.table_name
      end

      def table_name
        self.class.table_name
      end
    end

    macro included
      def self.sti_column_name : String?
        nil
      end

      def self.sti_scope_type_value : String?
        nil
      end

      def self.sti_persisted_type_value : String?
        nil
      end

      def self.__sti_class_for(type_value : String) : Luna::BaseModel.class | Nil
        Luna::Sti.lookup(self, type_value)
      end

      def self.__read_row_hash(rs : DB::ResultSet) : Hash(String, DB::Any)
        row = Hash(String, DB::Any).new
        rs.each_column do |column_name|
          row[column_name] = rs.read(DB::Any)
        end
        row
      end

      def self.__from_db_hash(row : Hash(String, DB::Any)) : self
        obj = new
        row.each do |column_name, value|
          obj.__assign_field_from_db_any(column_name, value)
        end
        obj.fetched = true
        obj.clear_changes_information
        obj
      end

      protected def self.__db_any_to_sti_type(value : DB::Any) : String?
        case value
        when String
          value
        when Nil
          nil
        else
          value.to_s
        end
      end

      private def apply_sti_discriminator!
        return unless (col = self.class.sti_column_name)
        return unless (type = self.class.sti_persisted_type_value)
        __assign_field_from_db_any(col, type.as(DB::Any))
      end
    end
  end
end
