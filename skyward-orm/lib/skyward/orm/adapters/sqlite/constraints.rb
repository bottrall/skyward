# frozen_string_literal: true

# SQLite keeps no catalog of constraints, only each table's CREATE TABLE
# statement, so their names, kinds, columns and definitions are read from that.
module Skyward::ORM::Adapters::SQLite::Constraints
  extend self

  # A token's kind, its text with any quotes removed, and where it starts and
  # ends in the statement, so a definition can be cut from the statement as written.
  # @rbs!
  #   type token = [Symbol, String, Integer, Integer]

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

  # The words that start a column's next constraint, or its default or collation.
  COLUMN_CLAUSES = %w[
    CONSTRAINT PRIMARY NOT NULL UNIQUE CHECK DEFAULT COLLATE REFERENCES GENERATED AS
  ].freeze #: Array[String]

  # A reference's ON DELETE SET NULL and SET DEFAULT end in these.
  SET_TO = %w[NULL DEFAULT].freeze #: Array[String]

  # @rbs sql: String
  # @rbs columns: Array[Symbol]
  # @rbs return: Array[Skyward::ORM::Catalog::Constraint]
  def read(sql, columns) = definitions(sql).flat_map { |definition| constraints(sql, definition, columns) }

  private

  # The scan covers every character, since its last alternative matches any
  # one, so each token starts where the one before it ends.
  # @rbs sql: String
  # @rbs return: Array[Array[[token, Integer]]]
  def definitions(sql)
    texts = sql.scan(TOKEN) #: Array[String]
    starts = texts.each_with_object([0]) { |text, offsets| offsets << (offsets.fetch(-1) + text.length) }
    tokens = texts.each_with_index.filter_map { |text, index| token(text, starts.fetch(index)) }
    body = tokens.drop_while { |token| token.first != :open }.drop(1)
    depths = body.each_with_object([0]) { |token, levels| levels << (levels.fetch(-1) + DEPTH.fetch(token.first, 0)) }
    paired = body.each_with_index.map { |token, index| [token, depths.fetch(index)] } #: Array[[token, Integer]]
    paired.take_while { |token, depth| !(depth.zero? && token.first == :close) }
          .chunk { |token, depth| depth.zero? && token.first == :comma ? :_separator : true }
          .map { |_, definition| definition }
  end

  # @rbs text: String
  # @rbs start: Integer
  # @rbs return: token?
  def token(text, start)
    finish = start + text.length
    case text
    when %r{\A(?:\s|--|/\*)} then nil
    when /\A"/ then [:name, text[1...-1].to_s.gsub('""', '"'), start, finish]
    when /\A`/ then [:name, text[1...-1].to_s.gsub("``", "`"), start, finish]
    when /\A\[/ then [:name, text[1...-1].to_s, start, finish]
    when /\A'/ then [:string, text, start, finish]
    when "(" then [:open, text, start, finish]
    when ")" then [:close, text, start, finish]
    when "," then [:comma, text, start, finish]
    when /\A[\p{L}_]/ then [:word, text, start, finish]
    else [:other, text, start, finish]
    end
  end

  # A column's own constraints are on that column. A table constraint names
  # its columns in parentheses, and a check is on the columns its expression
  # mentions.
  # @rbs sql: String
  # @rbs definition: Array[[token, Integer]]
  # @rbs columns: Array[Symbol]
  # @rbs return: Array[Skyward::ORM::Catalog::Constraint]
  def constraints(sql, definition, columns)
    tokens = definition.map(&:first)
    first = tokens.fetch(0)
    column = first[1].to_sym unless TABLE_CONSTRAINTS.include?(word(first))
    definition.each_with_index.filter_map do |(token, depth), index|
      kind = KINDS[word(token).to_s] if depth.zero?
      # A table's FOREIGN KEY is followed by its REFERENCES.
      next if kind.nil? || (column.nil? && word(token) == "REFERENCES")

      Skyward::ORM::Catalog::Constraint.new(
        name: (tokens.fetch(index - 1)[1] if index > 1 && word(tokens.fetch(index - 2)) == "CONSTRAINT"),
        kind:,
        columns: column ? [column] : mentioned(first_parenthesized(definition.drop(index + 1)), columns),
        references: (referenced(tokens.drop(index)) if kind == :foreign_key),
        definition: column ? on_column(sql, kind, column, definition.drop(index)) : text(sql, tokens.drop(index))
      )
    end
  end

  # A column's constraint, written as the table constraint it's the same as.
  # @rbs sql: String
  # @rbs kind: Skyward::ORM::Catalog::constraint_kind
  # @rbs column: Symbol
  # @rbs rest: Array[[token, Integer]]
  # @rbs return: String
  def on_column(sql, kind, column, rest)
    case kind
    when :primary_key then "PRIMARY KEY (#{column})"
    when :unique then "UNIQUE (#{column})"
    when :check then text(sql, own(rest))
    else "FOREIGN KEY (#{column}) #{text(sql, own(rest))}"
    end
  end

  # A column constraint runs until the column's next clause. ON DELETE SET
  # NULL and NOT DEFERRABLE are inside a reference, though, not clauses of
  # their own.
  # @rbs rest: Array[[token, Integer]]
  # @rbs return: Array[token]
  def own(rest)
    tokens = rest.map(&:first)
    ending = rest.each_index.find do |index|
      next false if index.zero? || rest.fetch(index).last.positive?

      clause = word(tokens.fetch(index))
      following = tokens[index + 1]
      COLUMN_CLAUSES.include?(clause.to_s) &&
        !(SET_TO.include?(clause) && word(tokens.fetch(index - 1)) == "SET") &&
        !(clause == "NOT" && following && word(following) == "DEFERRABLE")
    end
    tokens.take(ending || tokens.size)
  end

  # @rbs sql: String
  # @rbs tokens: Array[token]
  # @rbs return: String
  def text(sql, tokens) = sql[tokens.fetch(0)[2]...tokens.fetch(-1)[3]].to_s

  # @rbs token: token
  # @rbs return: String?
  def word(token) = (token[1].upcase if token.first == :word)

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
  def referenced(tokens) = tokens.drop_while { |token| word(token) != "REFERENCES" }.fetch(1)[1].to_sym
end
