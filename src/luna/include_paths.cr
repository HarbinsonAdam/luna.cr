module Luna::IncludePaths
  # Produces paths like:
  # [:author]
  # [:author, :posts]
  # [:author, :posts, :comments]
  def self.build(*incs : Symbol, **nested) : Array(Array(Symbol))
    paths = [] of Array(Symbol)
    incs.each { |s| paths << [s] }
    add_nested(paths, [] of Symbol, nested)
    paths
  end

  def self.build(**nested) : Array(Array(Symbol))
    paths = [] of Array(Symbol)
    add_nested(paths, [] of Symbol, nested) unless nested.empty?
    paths
  end

  private def self.add_nested(paths : Array(Array(Symbol)), prefix : Array(Symbol), nt : NamedTuple)
    nt.each do |k, v|
      p = prefix + [k]
      paths << p
      add_value(paths, p, v)
    end
  end

  private def self.add_value(paths : Array(Array(Symbol)), prefix : Array(Symbol), v)
    case v
    when Symbol
      paths << (prefix + [v])
    when Array(Symbol)
      v.each { |sym| paths << (prefix + [sym]) }
    when NamedTuple
      add_nested(paths, prefix, v)
    else
      raise ArgumentError.new("Unsupported includes nesting value: #{v.class}")
    end
  end
end
