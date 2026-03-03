module Luna
  module Context
    @[ThreadLocal]
    @@conn : DB::Connection?
    @[ThreadLocal]
    @@transaction_depth = 0

    def self.with_connection(conn : DB::Connection, &block)
      prev = @@conn
      @@conn = conn
      begin
        yield
      ensure
        @@conn = prev
      end
    end

    def self.current_connection : DB::Connection?
      @@conn
    end

    def self.transaction_depth : Int32
      @@transaction_depth
    end

    def self.in_transaction? : Bool
      @@transaction_depth > 0
    end

    def self.with_transaction(&block)
      @@transaction_depth += 1
      begin
        yield
      ensure
        @@transaction_depth -= 1
      end
    end
  end
end
