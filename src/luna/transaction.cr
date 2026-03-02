module Luna
  # Global transaction helper, similar to ActiveRecord::Base.transaction.
  # Raises rollback of current tx when Luna::Rollback is raised and swallows it.
  def self.transaction(connection_name : Symbol = :default, &block)
    if Luna::Context.current_connection
      begin
        yield
      rescue Luna::Rollback
      end
      return
    end

    db = Setup.db_connections(connection_name)
    begin
      db.transaction do |tx|
        Luna::Context.with_connection(tx.connection) { yield }
      end
    rescue Luna::Rollback
    end
  end
end
