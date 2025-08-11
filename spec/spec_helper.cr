require "spec"
require "../src/custom-orm"

DB_FILE = "./spec/test.db"

Spec.before_suite do
  # Remove any old test DB
  File.delete(DB_FILE) if File.exists?(DB_FILE)

  # Register a single-connection file-based SQLite DB for both default and reports
  CustomOrm::Setup.register :default, "sqlite3://#{DB_FILE}"
  CustomOrm::Setup.register :reports, "sqlite3://#{DB_FILE}"
end

Spec.after_suite do
  # Clean up
  #File.delete(DB_FILE) if File.exists?(DB_FILE)
end