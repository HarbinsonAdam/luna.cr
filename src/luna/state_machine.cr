module Luna::StateMachine
  private def __luna_raise_invalid_transition!(column : Symbol, from_state : Symbol, to_state : Symbol, event : Symbol? = nil) : NoReturn
    raise Luna::InvalidStateTransition.new(self.class.name, column, from_state, to_state, event)
  end

  macro state_machine(column, enum_type, events)
    {% unless enum_type.resolve < Enum %}
      {% raise "state_machine enum_type must inherit Enum" %}
    {% end %}

    {% field_type = FIELDS[column.id][:klass].resolve %}
    {% if field_type.nilable? %}
      {% state_enum_type = field_type.union_types.reject(&.nilable?).first %}
    {% else %}
      {% state_enum_type = field_type %}
    {% end %}
    {% unless state_enum_type == enum_type.resolve %}
      {% raise "state_machine enum_type #{enum_type.resolve} does not match attribute #{column.id} type #{state_enum_type}" %}
    {% end %}

    # Compile-time DSL validation.
    {% unless events.is_a?(NamedTupleLiteral) %}
      {% raise "state_machine events must be a NamedTuple literal" %}
    {% end %}
    {% for event_name, config in events %}
      {% unless config.is_a?(NamedTupleLiteral) %}
        {% raise "state_machine event #{event_name.id} config must be a NamedTuple literal" %}
      {% end %}
      {% has_from = false %}
      {% has_to = false %}
      {% for cfg_key, cfg_val in config %}
        {% if cfg_key.id == "from" %}
          {% has_from = true %}
          {% unless cfg_val.is_a?(SymbolLiteral) || cfg_val.is_a?(ArrayLiteral) %}
            {% raise "state_machine event #{event_name.id} :from must be a Symbol or Array(Symbol)" %}
          {% end %}
          {% if cfg_val.is_a?(ArrayLiteral) %}
            {% for from_state in cfg_val %}
              {% unless from_state.is_a?(SymbolLiteral) %}
                {% raise "state_machine event #{event_name.id} :from array must contain only symbols" %}
              {% end %}
            {% end %}
          {% end %}
        {% elsif cfg_key.id == "to" %}
          {% has_to = true %}
          {% unless cfg_val.is_a?(SymbolLiteral) %}
            {% raise "state_machine event #{event_name.id} :to must be a Symbol" %}
          {% end %}
        {% elsif cfg_key.id == "before" || cfg_key.id == "after" %}
          {% unless cfg_val.is_a?(SymbolLiteral) %}
            {% raise "state_machine event #{event_name.id} :#{cfg_key.id} must be a Symbol method name" %}
          {% end %}
        {% end %}
      {% end %}
      {% unless has_from && has_to %}
        {% raise "state_machine event #{event_name.id} requires :from and :to" %}
      {% end %}
    {% end %}

    private def __luna_{{column.id}}_to_symbol(value : {{enum_type.resolve}}) : Symbol
      case value
      {% for constant in enum_type.resolve.constants %}
      when {{enum_type.resolve}}::{{constant.id}}
        :{{constant.stringify.underscore.downcase.id}}
      {% end %}
      else
        raise ArgumentError.new("Unknown {{enum_type.resolve}} enum value: #{value}")
      end
    end

    private def __luna_{{column.id}}_from_symbol!(value : Symbol) : {{enum_type.resolve}}
      {% for constant in enum_type.resolve.constants %}
      return {{enum_type.resolve}}::{{constant.id}} if value == :{{constant.stringify.underscore.downcase.id}}
      {% end %}
      raise ArgumentError.new("Unknown state symbol for {{enum_type.resolve}}: #{value}")
    end

    before_save :__luna_validate_state_machine_{{column.id}}

    def __luna_validate_state_machine_{{column.id}}
      return unless @fetched && {{column.id}}_changed?

      previous = {{column.id}}_was
      if previous
        from_enum = previous.not_nil!
        to_enum = {{column.id}}

        allowed = case from_enum
        {% for constant in enum_type.resolve.constants %}
          when {{enum_type.resolve}}::{{constant.id}}
            {% targets = [] of Nil %}
            {% for event_name, config in events %}
              {% from_arg = nil %}
              {% to_arg = nil %}
              {% for cfg_key, cfg_val in config %}
                {% if cfg_key.id == "from" %}
                  {% from_arg = cfg_val %}
                {% elsif cfg_key.id == "to" %}
                  {% to_arg = cfg_val %}
                {% end %}
              {% end %}
              {% include_state = false %}
              {% if from_arg.is_a?(ArrayLiteral) %}
                {% for from_state in from_arg %}
                  {% if from_state.id.stringify == constant.stringify.underscore.downcase %}
                    {% include_state = true %}
                  {% end %}
                {% end %}
              {% else %}
                {% if from_arg.id.stringify == constant.stringify.underscore.downcase %}
                  {% include_state = true %}
                {% end %}
              {% end %}
              {% if include_state %}
                (to_enum == {{enum_type.resolve}}::{{to_arg.id.upcase.id}}) ||
              {% end %}
            {% end %}
            false
        {% end %}
        else
          false
        end

        unless allowed
          __luna_raise_invalid_transition!(
            :{{column.id}},
            __luna_{{column.id}}_to_symbol(from_enum),
            __luna_{{column.id}}_to_symbol(to_enum)
          )
        end
      end
    end

    {% for event_name, config in events %}
      {% from_arg = nil %}
      {% to_arg = nil %}
      {% before_hook = nil %}
      {% after_hook = nil %}
      {% for cfg_key, cfg_val in config %}
        {% if cfg_key.id == "from" %}
          {% from_arg = cfg_val %}
        {% elsif cfg_key.id == "to" %}
          {% to_arg = cfg_val %}
        {% elsif cfg_key.id == "before" %}
          {% before_hook = cfg_val %}
        {% elsif cfg_key.id == "after" %}
          {% after_hook = cfg_val %}
        {% end %}
      {% end %}
      {% if from_arg.nil? || to_arg.nil? %}
        {% raise "state_machine event #{event_name.id} requires :from and :to" %}
      {% end %}

      def {{event_name.id}} : self
        current_enum = {{column.id}}
        allowed = false
        {% if from_arg.is_a?(ArrayLiteral) %}
          {% for from_state in from_arg %}
        allowed ||= current_enum == {{enum_type.resolve}}::{{from_state.id.upcase.id}}
          {% end %}
        {% else %}
        allowed ||= current_enum == {{enum_type.resolve}}::{{from_arg.id.upcase.id}}
        {% end %}

        unless allowed
          __luna_raise_invalid_transition!(
            :{{column.id}},
            __luna_{{column.id}}_to_symbol(current_enum),
            :{{to_arg.id}},
            :{{event_name.id}}
          )
        end

        {% if before_hook %}
        {{before_hook.id}}
        {% end %}

        self.{{column.id}} = {{enum_type.resolve}}::{{to_arg.id.upcase.id}}

        {% if after_hook %}
        {{after_hook.id}}
        {% end %}

        self
      end

      def {{event_name.id}}! : self
        {{event_name.id}}
        save
        self
      end
    {% end %}

    {% for constant in enum_type.resolve.constants %}
    def {{column.id}}_{{constant.stringify.underscore.downcase.id}}? : Bool
      {{column.id}} == {{enum_type.resolve}}::{{constant.id}}
    end
    {% end %}
  end
end
