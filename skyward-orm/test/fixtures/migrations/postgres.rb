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

  def default_expression(expression) = expression

  def encode(value) = value.is_a?(Symbol) ? value.name : value
end
