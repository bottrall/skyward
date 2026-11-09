# frozen_string_literal: true

# SQLite keeps no catalog of constraints, only each table's CREATE TABLE
# statement, so their names, kinds and columns are read from that.
module Skyward::ORM::Adapters::SQLite::Constraints
  extend self

  # @rbs!
  #   type token = [Symbol, String]

  TOKEN = Regexp.union(
    %r{\s+|--[^\n]*|/\*.*?\*/}m,
    /"(?:[^"]|"")*"|`(?:[^`]|``)*`|\[[^\]]*\]/,
    /'(?:[^']|'')*'/,
    /[\p{L}_][\p{L}\p{N}_$]*/,
    /./m
  ) #: Regexp

  DEPTH = { open: 1, close: -1 }.freeze #: Hash[Symbol, Integer]

  NAMES = %i[word name].freeze #: Array[Symbol]

  TABLE_CONSTRAINTS = %w[CONSTRAINT PRIMARY UNIQUE CHECK FOREIGN].freeze #: Array[String]

  KINDS = {
    "PRIMARY" => :primary_key,
    "UNIQUE" => :unique,
    "CHECK" => :check,
    "FOREIGN" => :foreign_key,
    "REFERENCES" => :foreign_key
  }.freeze #: Hash[String, Skyward::ORM::Catalog::constraint_kind]

  # @rbs sql: String
  # @rbs columns: Array[Symbol]
  # @rbs return: Array[Skyward::ORM::Catalog::Constraint]
  def read(sql, columns) = definitions(sql).flat_map { |definition| constraints(definition, columns) }

  private

  # @rbs sql: String
  # @rbs return: Array[Array[[token, Integer]]]
  def definitions(sql)
    texts = sql.scan(TOKEN) #: Array[String]
    body = texts.filter_map { |text| token(text) }.drop_while { |token| token.first != :open }.drop(1)
    depths = body.each_with_object([0]) { |token, levels| levels << (levels.fetch(-1) + DEPTH.fetch(token.first, 0)) }
    paired = body.each_with_index.map { |token, index| [token, depths.fetch(index)] } #: Array[[token, Integer]]
    paired.take_while { |token, depth| !(depth.zero? && token.first == :close) }
          .chunk { |token, depth| depth.zero? && token.first == :comma ? :_separator : true }
          .map { |_, definition| definition }
  end

  # @rbs text: String
  # @rbs return: token?
  def token(text)
    case text
    when %r{\A(?:\s|--|/\*)} then nil
    when /\A"/ then [:name, text[1...-1].to_s.gsub('""', '"')]
    when /\A`/ then [:name, text[1...-1].to_s.gsub("``", "`")]
    when /\A\[/ then [:name, text[1...-1].to_s]
    when /\A'/ then [:string, text]
    when "(" then [:open, text]
    when ")" then [:close, text]
    when "," then [:comma, text]
    when /\A[\p{L}_]/ then [:word, text]
    else [:other, text]
    end
  end

  # A column's own constraints are on that column. A table constraint names
  # its columns in parentheses, and a check is on the columns its expression
  # mentions.
  # @rbs definition: Array[[token, Integer]]
  # @rbs columns: Array[Symbol]
  # @rbs return: Array[Skyward::ORM::Catalog::Constraint]
  def constraints(definition, columns)
    tokens = definition.map(&:first)
    first = tokens.fetch(0)
    column = first.last.to_sym unless TABLE_CONSTRAINTS.include?(word(first))
    definition.each_with_index.filter_map do |(token, depth), index|
      kind = KINDS[word(token).to_s] if depth.zero?
      # A table's FOREIGN KEY is followed by its REFERENCES.
      next if kind.nil? || (column.nil? && word(token) == "REFERENCES")

      Skyward::ORM::Catalog::Constraint.new(
        name: (tokens.fetch(index - 1).last if index > 1 && word(tokens.fetch(index - 2)) == "CONSTRAINT"),
        kind:,
        columns: column ? [column] : mentioned(first_parenthesized(definition.drop(index + 1)), columns),
        references: (referenced(tokens.drop(index)) if kind == :foreign_key)
      )
    end
  end

  # @rbs token: token
  # @rbs return: String?
  def word(token) = (token.last.upcase if token.first == :word)

  # @rbs rest: Array[[token, Integer]]
  # @rbs return: Array[token]
  def first_parenthesized(rest)
    rest.drop_while { |token, _| token.first != :open }.drop(1).take_while { |_, depth| depth.positive? }.map(&:first)
  end

  # @rbs tokens: Array[token]
  # @rbs columns: Array[Symbol]
  # @rbs return: Array[Symbol]
  def mentioned(tokens, columns)
    tokens.filter_map do |kind, text|
      columns.find { |column| column.name.casecmp?(text) } if NAMES.include?(kind)
    end.uniq
  end

  # @rbs tokens: Array[token]
  # @rbs return: Symbol
  def referenced(tokens) = tokens.drop_while { |token| word(token) != "REFERENCES" }.fetch(1).last.to_sym
end
