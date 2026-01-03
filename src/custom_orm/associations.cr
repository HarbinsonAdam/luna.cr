# src/custom_orm/associations.cr
module CustomOrm::Associations
  # This module is included by BaseModel.
  # It provides:
  # - belongs_to / has_one / has_many macros
  # - eager loading via Relation.includes(:assoc)
  #
  # Design:
  # - Each association macro defines:
  #   - lazy accessor (uses @__preloaded_* if present)
  #   - typed setter __set_preloaded_<name>
  #   - typed class preloader __eager_load_<name>(records)
  #   - overrides __eager_load_one(records, inc) via previous_def

  macro included
    macro inherited
      # Dispatch entrypoint called by Relation after the base query.
      def self.__eager_load(records : Array(self), includes : Array(Symbol))
        return if includes.empty?
        includes.each do |inc|
          __eager_load_one(records, inc)
        end
      end

      # Default: unknown include
      def self.__eager_load_one(records : Array(self), inc : Symbol)
        raise "Unknown include '#{inc}' for #{self.name}"
      end
    end
  end

  # ------------------------------------------------------------
  # belongs_to
  # ------------------------------------------------------------
  #
  # Example:
  #   belongs_to author, klass: Author, foreign_key: author_id
  #
  macro belongs_to(name, klass, foreign_key = nil, primary_key = "id")
    {% assoc = name.id %}
    {% fk = (foreign_key || "#{assoc}_id").id %}
    {% pk = primary_key.id %}

    # cache
    @__preloaded_{{assoc}} : {{klass}}?

    # setter for preloader
    def __set_preloaded_{{assoc}}(val : {{klass}}?)
      @__preloaded_{{assoc}} = val
    end

    # lazy accessor
    def {{assoc}} : {{klass}}?
      if pre = @__preloaded_author
        return pre
      end
      
      fk_val = self.{{fk}}
      return nil unless fk_val
      {{klass}}.find(fk_val.as(Int64))
    end

    # typed eager loader for this association
    def self.__eager_load_{{assoc}}(records : Array(self))
      # collect foreign keys
      ids = [] of Int64
      records.each do |r|
        v = r.{{fk}}
        next unless v
        ids << v.as(Int64)
      end
      ids.uniq!
      return if ids.empty?

      parents = {{klass}}.rel.where_in({{pk.stringify}}, ids.map(&.as(DB::Any))).all
      by_id = Hash(Int64, {{klass}}).new
      parents.each do |p|
        by_id[p.{{pk}}] = p
      end

      records.each do |r|
        v = r.{{fk}}
        if v
          r.__set_preloaded_{{assoc}}(by_id[v.as(Int64)]?)
        else
          r.__set_preloaded_{{assoc}}(nil)
        end
      end
    end

    # hook into dispatcher
    def self.__eager_load_one(records : Array(self), inc : Symbol)
      if inc == {{assoc.symbolize}}
        __eager_load_{{assoc}}(records)
      else
        previous_def(records, inc)
      end
    end
  end

  # ------------------------------------------------------------
  # has_many
  # ------------------------------------------------------------
  #
  # Example:
  #   has_many posts, klass: Post, foreign_key: author_id
  #
  macro has_many(name, klass, foreign_key = nil, primary_key = "id")
    {% assoc = name.id %}
    {% default_fk = "#{@type.name.split("::").last.underscore}_id" %}
    {% fk = (foreign_key || default_fk).id %}
    {% pk = primary_key.id %}

    @__preloaded_{{assoc}} : Array({{klass}})?

    def __set_preloaded_{{assoc}}(val : Array({{klass}}))
      @__preloaded_{{assoc}} = val
    end

    def {{assoc}} : Array({{klass}})
      if pre = @__preloaded_{{assoc}}
        return pre
      end
      
      # lazy query
      {{klass}}.rel.where({ {{fk.id}}: self.{{pk}}.as(DB::Any) }).all
    end

    def self.__eager_load_{{assoc}}(records : Array(self))
      parent_ids = [] of Int64
      records.each { |r| parent_ids << r.{{pk}} }
      parent_ids.uniq!
      return if parent_ids.empty?

      children = {{klass}}.rel.where_in({{fk.stringify}}, parent_ids.map(&.as(DB::Any))).all

      grouped = Hash(Int64, Array({{klass}})).new { |h, k| h[k] = [] of {{klass}} }
      children.each do |child|
        key = child.{{fk}}.as(Int64)
        grouped[key] << child
      end

      records.each do |r|
        r.__set_preloaded_{{assoc}}(grouped[r.{{pk}}]? || [] of {{klass}})
      end
    end

    def self.__eager_load_one(records : Array(self), inc : Symbol)
      if inc == {{assoc.symbolize}}
        __eager_load_{{assoc}}(records)
      else
        previous_def(records, inc)
      end
    end
  end

  # ------------------------------------------------------------
  # has_one
  # ------------------------------------------------------------
  #
  # Example:
  #   has_one profile, klass: Profile, foreign_key: author_id
  #
  macro has_one(name, klass, foreign_key = nil, primary_key = "id")
    {% assoc = name.id %}
    {% default_fk = "#{@type.name.split("::").last.underscore}_id" %}
    {% fk = (foreign_key || default_fk).id %}
    {% pk = primary_key.id %}

    @__preloaded_{{assoc}} : {{klass}}?

    def __set_preloaded_{{assoc}}(val : {{klass}}?)
      @__preloaded_{{assoc}} = val
    end

    def {{assoc}} : {{klass}}?
      if pre = @__preloaded_{{assoc}}
        return pre
      end

      {{klass}}.rel.where({ {{fk.id}}: self.{{pk}}.as(DB::Any) }).first
    end

    def self.__eager_load_{{assoc}}(records : Array(self))
      parent_ids = [] of Int64
      records.each { |r| parent_ids << r.{{pk}} }
      parent_ids.uniq!
      return if parent_ids.empty?

      rows = {{klass}}.rel.where_in({{fk.stringify}}, parent_ids.map(&.as(DB::Any))).all

      by_fk = Hash(Int64, {{klass}}).new
      rows.each do |row|
        by_fk[row.{{fk}}.as(Int64)] = row
      end

      records.each do |r|
        r.__set_preloaded_{{assoc}}(by_fk[r.{{pk}}]?)
      end
    end

    def self.__eager_load_one(records : Array(self), inc : Symbol)
      if inc == {{assoc.symbolize}}
        __eager_load_{{assoc}}(records)
      else
        previous_def(records, inc)
      end
    end
  end
end
