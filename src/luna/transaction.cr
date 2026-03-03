module Luna
  # Global transaction helper, similar to ActiveRecord::Base.transaction.
  # Raises rollback of current tx when Luna::Rollback is raised and swallows it.
  def self.transaction(connection_name : Symbol = :default, &)
    if Luna::Context.current_connection
      begin
        Luna::Context.with_transaction { yield }
      rescue Luna::Rollback
      end
      return
    end

    db = Setup.db_connections(connection_name)
    tx_started_at = Time.monotonic
    Luna::Logging.log_transaction("begin transaction")
    begin
      db.transaction do |tx|
        Luna::Context.with_connection(tx.connection) do
          Luna::Context.with_transaction { yield }
        end
      end
      elapsed_ms = (Time.monotonic - tx_started_at).total_milliseconds
      Luna::Logging.log_transaction("commit transaction", elapsed_ms)
    rescue Luna::Rollback
      elapsed_ms = (Time.monotonic - tx_started_at).total_milliseconds
      Luna::Logging.log_transaction("rollback transaction", elapsed_ms)
    end
  end
end
