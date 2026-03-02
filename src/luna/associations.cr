module Luna::Associations
  macro included
    macro inherited
      # ------------------------------------------------------------
      # Default preload hooks (overridden per-association via previous_def)
      # ------------------------------------------------------------
      def set_preloaded(name : Symbol, value : Luna::BaseModel?)
        # default: ignore
      end

      def set_preloaded_many(name : Symbol, value : Array(Luna::BaseModel))
        # default: ignore
      end

      def get_preloaded(name : Symbol) : Luna::BaseModel?
        nil
      end

      def get_preloaded_many(name : Symbol) : Array(Luna::BaseModel)?
        nil
      end

      # ------------------------------------------------------------
      # Deep eager load entry point
      # ------------------------------------------------------------
      def self.__eager_load_paths(records : Array(self), paths : Array(Array(Symbol)))
        return if records.empty? || paths.empty?

        grouped = Hash(Symbol, Array(Array(Symbol))).new { |h, k| h[k] = [] of Array(Symbol) }
        paths.each do |p|
          next if p.empty?
          grouped[p[0]] << p
        end

        grouped.each do |first, ps|
          # preload first hop for all records
          __eager_load_first_hop(records, first)

          # recurse for any deeper paths
          next_paths = ps.compact_map { |p| p.size > 1 ? p[1..] : nil }
          next if next_paths.empty?

          children = __collect_children_for(records, first)
          next if children.empty?

          # call eager loader on the associated klass (installed by macros below)
          __eager_load_children_for(first, children, next_paths)
        end
      end

      # This gets overridden per association macro to route to the right klass
      private def self.__eager_load_children_for(first : Symbol, children : Array(Luna::BaseModel), next_paths : Array(Array(Symbol)))
        # default: do nothing
      end

      private def self.__collect_children_for(records : Array(self), inc : Symbol) : Array(Luna::BaseModel)
        out = [] of Luna::BaseModel

        # try single preload store
        records.each do |r|
          if c = r.get_preloaded(inc)
            out << c
          end
        end

        # try many preload store
        records.each do |r|
          if arr = r.get_preloaded_many(inc)
            arr.each { |x| out << x }
          end
        end

        out
      end

      # ------------------------------------------------------------
      # First-hop dispatcher (overridden per-association via previous_def)
      # ------------------------------------------------------------
      private def self.__eager_load_first_hop(records : Array(self), inc : Symbol)
        raise "Unknown include '#{inc}' for #{self.name}"
      end

      # ------------------------------------------------------------
      # Eager load implementations
      # ------------------------------------------------------------
      private def self.__eager_load_belongs_to(records : Array(self), name : Symbol,
                                               klass : K.class, fk : String, pk : String) forall K
        ids = [] of DB::Any
        records.each do |r|
          if v = r.read_attribute?(fk)
            ids << v.as(DB::Any)
          end
        end
        ids.uniq!
        return if ids.empty?

        rows  = klass.rel.where_in(pk, ids).all
        by_pk = Hash(DB::Any, K).new
        rows.each do |row|
          by_pk[row.read_attribute(pk).as(DB::Any)] = row
        end

        records.each do |r|
          fk_val = r.read_attribute?(fk)
          r.set_preloaded(name, fk_val ? by_pk[fk_val.as(DB::Any)]? : nil)
        end
      end

      private def self.__eager_load_has_one(records : Array(self), name : Symbol,
                                            klass : K.class, fk : String, pk : String) forall K
        parent_ids = records.compact_map { |r| r.read_attribute?(pk).try &.as(DB::Any) }.uniq
        return if parent_ids.empty?

        rows  = klass.rel.where_in(fk, parent_ids).all
        by_fk = Hash(DB::Any, K).new
        rows.each do |row|
          by_fk[row.read_attribute(fk).as(DB::Any)] = row
        end

        records.each do |r|
          key = r.read_attribute(pk).as(DB::Any)
          r.set_preloaded(name, by_fk[key]?)
        end
      end

      private def self.__eager_load_has_many(records : Array(self), name : Symbol,
                                             klass : K.class, fk : String, pk : String) forall K
        parent_ids = records.compact_map { |r| r.read_attribute?(pk).try &.as(DB::Any) }.uniq
        return if parent_ids.empty?

        rows = klass.rel.where_in(fk, parent_ids).all

        grouped = Hash(DB::Any, Array(K)).new { |h, k| h[k] = [] of K }
        rows.each do |row|
          key = row.read_attribute(fk).as(DB::Any)
          grouped[key] << row
        end

        records.each do |r|
          key = r.read_attribute(pk).as(DB::Any)
          # IMPORTANT: we pass Array(K) into the per-association setter (generated below)
          arr = grouped[key]? || [] of K
          r.set_preloaded_many(name, arr.map(&.as(Luna::BaseModel)))
        end
      end
    end
  end

  # ------------------------------------------------------------
  # Association macros
  # ------------------------------------------------------------

  macro belongs_to(name, klass, foreign_key = nil, primary_key = "id")
    {% assoc = name.id %}
    {% fk = (foreign_key || "#{assoc}_id").id %}
    {% pk = primary_key.id %}

    @__preloaded_{{assoc}} : {{klass}}? = nil

    # preload hooks
    def set_preloaded(name : Symbol, value : Luna::BaseModel?)
      if name == {{assoc.symbolize}}
        @__preloaded_{{assoc}} = value.as({{klass}}?)
        return
      end
      previous_def
    end

    def get_preloaded(name : Symbol) : Luna::BaseModel?
      return @__preloaded_{{assoc}} if name == {{assoc.symbolize}}
      previous_def
    end

    # eager loader dispatch (first hop)
    private def self.__eager_load_first_hop(records : Array(self), inc : Symbol)
      if inc == {{assoc.symbolize}}
        __eager_load_belongs_to(records, {{assoc.symbolize}}, {{klass}}, {{fk.stringify}}, {{pk.stringify}})
        return
      end
      previous_def
    end

    # eager loader dispatch (recurse)
    private def self.__eager_load_children_for(first : Symbol, children : Array(Luna::BaseModel), next_paths : Array(Array(Symbol)))
      if first == {{assoc.symbolize}}
        {{klass}}.__eager_load_paths(children.compact_map(&.as?({{klass}})), next_paths)
        return
      end
      previous_def
    end

    # lazy accessor
    def {{assoc}} : {{klass}}?
      return @__preloaded_{{assoc}} if @__preloaded_{{assoc}}

      fk_val = self.{{fk}}
      return nil unless fk_val
      {{klass}}.find(fk_val.as(Int64))
    end
  end

  macro has_one(name, klass, foreign_key = nil, primary_key = "id")
    {% assoc = name.id %}
    {% default_fk = "#{@type.name.split("::").last.underscore}_id" %}
    {% fk = (foreign_key || default_fk).id %}
    {% pk = primary_key.id %}

    @__preloaded_{{assoc}} : {{klass}}? = nil

    def set_preloaded(name : Symbol, value : Luna::BaseModel?)
      if name == {{assoc.symbolize}}
        @__preloaded_{{assoc}} = value.as({{klass}}?)
        return
      end
      previous_def
    end

    def get_preloaded(name : Symbol) : Luna::BaseModel?
      return @__preloaded_{{assoc}} if name == {{assoc.symbolize}}
      previous_def
    end

    private def self.__eager_load_first_hop(records : Array(self), inc : Symbol)
      if inc == {{assoc.symbolize}}
        __eager_load_has_one(records, {{assoc.symbolize}}, {{klass}}, {{fk.stringify}}, {{pk.stringify}})
        return
      end
      previous_def
    end

    private def self.__eager_load_children_for(first : Symbol, children : Array(Luna::BaseModel), next_paths : Array(Array(Symbol)))
      if first == {{assoc.symbolize}}
        {{klass}}.__eager_load_paths(children.compact_map(&.as?({{klass}})), next_paths)
        return
      end
      previous_def
    end

    def {{assoc}} : {{klass}}?
      return @__preloaded_{{assoc}} if @__preloaded_{{assoc}}
      {{klass}}.rel.where({ {{fk.id}}: self.{{pk}}.as(DB::Any) }).first
    end
  end

  macro has_many(name, klass, foreign_key = nil, primary_key = "id")
    {% assoc = name.id %}
    {% default_fk = "#{@type.name.split("::").last.underscore}_id" %}
    {% fk = (foreign_key || default_fk).id %}
    {% pk = primary_key.id %}

    @__preloaded_{{assoc}} : Array({{klass}})? = nil

    def set_preloaded_many(name : Symbol, value : Array(Luna::BaseModel))
      if name == {{assoc.symbolize}}
        @__preloaded_{{assoc}} = value.map(&.as({{klass}}))
        return
      end
      previous_def
    end

    def get_preloaded_many(name : Symbol) : Array(Luna::BaseModel)?
      if name == {{assoc.symbolize}}
        return @__preloaded_{{assoc}}.try &.map(&.as(Luna::BaseModel))
      end
      previous_def
    end

    private def self.__eager_load_first_hop(records : Array(self), inc : Symbol)
      if inc == {{assoc.symbolize}}
        __eager_load_has_many(records, {{assoc.symbolize}}, {{klass}}, {{fk.stringify}}, {{pk.stringify}})
        return
      end
      previous_def
    end

    private def self.__eager_load_children_for(first : Symbol, children : Array(Luna::BaseModel), next_paths : Array(Array(Symbol)))
      if first == {{assoc.symbolize}}
        {{klass}}.__eager_load_paths(children.compact_map(&.as?({{klass}})), next_paths)
        return
      end
      previous_def
    end

    def {{assoc}} : Array({{klass}})
      if pre = @__preloaded_{{assoc}}
        return pre
      end
      {{klass}}.rel.where({ {{fk.id}}: self.{{pk}}.as(DB::Any) }).all
    end
  end
end
