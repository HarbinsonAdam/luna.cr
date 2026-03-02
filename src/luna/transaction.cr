module Luna
  # Global transaction helper (uses :default)
  def self.transaction(&block)
    db = Setup.pool(:default) rescue nil
    if db
      db.transaction { yield }
    else
      # Fallback if only db_connections is exposed
      Setup.db_connections(:default).transaction { yield }
    end
  end
end
