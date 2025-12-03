module CustomOrm
  module Context
    @[ThreadLocal]
    @@conn : DB::Connection?

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
  end
end
