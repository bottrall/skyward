# frozen_string_literal: true

module RuboCop::Cop::Local
  class NoRawSql < RuboCop::Cop::Base
    MSG = 'Only Skyward ORM talks to the database.'

    DRIVERS = %r{\A(?:sqlite3|pg)(?:/|\z)}
    DRIVER_CONSTANTS = %i[SQLite3 PG].freeze

    RESTRICT_ON_SEND = %i[require].freeze

    def on_send(node)
      library = node.first_argument
      return unless node.receiver.nil? && library&.str_type?

      add_offense(node) if library.value.match?(DRIVERS)
    end

    def on_const(node)
      return unless DRIVER_CONSTANTS.include?(node.short_name)
      return unless node.namespace.nil? || node.namespace.cbase_type?

      add_offense(node)
    end
  end
end
