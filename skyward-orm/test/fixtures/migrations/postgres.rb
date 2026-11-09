# frozen_string_literal: true

# PostgreSQL's types and DDL, as the README writes them, so a migration's
# layout can be checked against the README's example.
module MigrationsFixtures::Postgres
  extend self

  SQL_TYPES = {
    integer: "bigint",
    float: "double precision",
    string: "text",
    bool: "boolean",
    date: "date",
    time: "timestamptz",
    enum: "text"
  }.freeze

  def sql_type(type) = SQL_TYPES[type]

  def identity = "GENERATED ALWAYS AS IDENTITY"

  def alters_in_place? = true

  # Enough for these tests: the type a migration writes, or none for untyped.
  def compatible?(type, sql_type) = SQL_TYPES[type].nil? || SQL_TYPES[type] == sql_type

  def default_expression(expression) = expression

  def encode(value) = value.is_a?(Symbol) ? value.name : value
end
