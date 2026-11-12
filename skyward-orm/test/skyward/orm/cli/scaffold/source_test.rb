# frozen_string_literal: true

require "test_helper"
require_relative "../../../../fixtures/migrations/migrations_fixtures"

describe Skyward::ORM::CLI::Scaffold::Source do
  source = Skyward::ORM::CLI::Scaffold::Source
  catalog = Skyward::ORM::Catalog
  postgresql = Skyward::ORM::Adapters::PostgreSQL
  sqlite = Skyward::ORM::Adapters::SQLite

  define_method(:column) do |name, type, nullable: false, default: nil|
    catalog::Column.new(name:, type:, nullable:, default:, generated: nil)
  end

  define_method(:constraint) do |name, kind, columns, definition, references: nil|
    catalog::Constraint.new(name:, kind:, columns:, references:, definition:)
  end

  define_method(:index) do |name, columns, definition, unique: false|
    catalog::Index.new(name:, columns:, unique:, definition:)
  end

  define_method(:table) do |name, columns, constraints: [], indexes: [], key: :id|
    primary_key = constraint("#{name}_pkey", :primary_key, [key], "PRIMARY KEY (#{key})")
    catalog::Table.new(name:, columns:, indexes:, constraints: [primary_key, *constraints])
  end

  define_method(:lists) { table(:lists, [column(:id, "bigint"), column(:name, "text")]) }

  # The class's body between its table and its readers, for a table with an
  # id, the columns and constraints given, and lists to reference.
  define_method(:body) do |columns = [], adapter: postgresql, classes: [], **keys|
    todos = table(:todos, [column(:id, "bigint"), *columns], **keys)
    text = source.text(todos, [lists, todos], adapter, classes)
    text[/^  table :todos\n(.*?)\n\n  # @dynamic/m, 1]
  end

  # Each column's reader, and any comment above it.
  define_method(:readers) do |columns, adapter: postgresql, constraints: []|
    todos = table(:todos, [column(:id, "bigint"), *columns], constraints:)
    source.text(todos, [todos], adapter, []).lines.drop_while { |line| !line.include?("@dynamic") }.drop(1)[0...-1]
  end

  # The default line's value for one column.
  define_method(:default) do |type, default, adapter: postgresql|
    body([column(:value, type, default:)], adapter:)[/^  default value: (.*)$/, 1]
  end

  describe ".text" do
    it "writes the README's Todo from the table PostgreSQL reads, its checks as PostgreSQL rewrites them" do
      todos = table(
        :todos,
        [
          column(:id, "bigint"),
          column(:list_id, "bigint"),
          column(:title, "text"),
          column(:priority, "text", default: "'normal'"),
          column(:due_on, "date", nullable: true),
          column(:done, "boolean", default: "false"),
          column(:created_at, "timestamp with time zone", default: "now()")
        ],
        constraints: [
          constraint(
            "todos_list_id_fkey",
            :foreign_key,
            [:list_id],
            "FOREIGN KEY (list_id) REFERENCES lists(id) ON DELETE CASCADE",
            references: :lists
          ),
          constraint(
            "todos_priority_check",
            :check,
            [:priority],
            "CHECK ((priority = ANY (ARRAY['low'::text, 'normal'::text, 'high'::text])))"
          ),
          constraint("todos_title_check", :check, [:title], "CHECK (((length(title) >= 1) AND (length(title) <= 200)))")
        ],
        indexes: [
          index(
            "todos_list_id_done_index",
            %i[list_id done],
            "CREATE INDEX todos_list_id_done_index ON public.todos USING btree (list_id, done)"
          )
        ]
      )
      expected = <<~RUBY
        # rbs_inline: enabled

        class Todo < Skyward::ORM::Record
          table :todos
          references :list_id, MigrationsFixtures::List, on_delete: :cascade
          default priority: :normal, done: false, created_at: Skyward.sql("now()")
          check :title, Skyward.sql("((length(title) >= 1) AND (length(title) <= 200))")
          index :list_id, :done

          # @dynamic id, list_id, title, priority, due_on, done, created_at
          attr_reader :id          #: Integer
          attr_reader :list_id     #: Integer
          attr_reader :title       #: String
          attr_reader :priority    #: :low | :normal | :high
          attr_reader :due_on      #: Date?
          attr_reader :done        #: bool
          attr_reader :created_at  #: Time
        end
      RUBY

      assert_equal expected, source.text(todos, [lists, todos], postgresql, [MigrationsFixtures::List])
    end

    it "starts with @rbs use Skyward::ORM::* when a column is a uuid, int32 or int16" do
      header = %w[uuid integer smallint].map do |type|
        todos = table(:todos, [column(:id, "bigint"), column(:value, type)])
        source.text(todos, [todos], postgresql, []).lines.take(2)
      end

      assert_equal [["# rbs_inline: enabled\n", "# @rbs use Skyward::ORM::*\n"]] * 3, header
    end

    it "comments on what the class can't declare below table, as what skyward migration will drop" do
      columns = [column(:list_id, "bigint"), column(:list_name, "text"), column(:a, "bigint"), column(:b, "bigint")]
      constraints = [
        constraint(
          "todos_list_fkey",
          :foreign_key,
          %i[list_id list_name],
          "FOREIGN KEY (list_id, list_name) REFERENCES lists(id, name)",
          references: :lists
        ),
        constraint(
          "todos_list_name_fkey",
          :foreign_key,
          [:list_name],
          "FOREIGN KEY (list_name) REFERENCES lists(name)",
          references: :lists
        ),
        constraint("todos_check", :check, %i[a b], "CHECK ((a > b))"),
        constraint(nil, :check, [], "CHECK (true)")
      ]
      indexes = [
        index("todos_lower_idx", [], "CREATE INDEX todos_lower_idx ON public.todos USING btree (lower(list_name))"),
        index("todos_a_idx", [:a], "CREATE INDEX todos_a_idx ON public.todos USING btree (a) WHERE (b > 0)"),
        index("todos_b_idx", [:b], "CREATE INDEX todos_b_idx ON public.todos USING hash (b)"),
        index("todos_b_desc_idx", [:b], "CREATE INDEX todos_b_desc_idx ON public.todos USING btree (b DESC)")
      ]
      expected = <<~RUBY.chomp
        # `skyward migration` will drop these, since a table class can't declare them:
        #   CONSTRAINT todos_list_fkey FOREIGN KEY (list_id, list_name) REFERENCES lists(id, name)
        #   CONSTRAINT todos_list_name_fkey FOREIGN KEY (list_name) REFERENCES lists(name)
        #   CONSTRAINT todos_check CHECK ((a > b))
        #   CHECK (true)
        #   CREATE INDEX todos_lower_idx ON public.todos USING btree (lower(list_name))
        #   CREATE INDEX todos_a_idx ON public.todos USING btree (a) WHERE (b > 0)
        #   CREATE INDEX todos_b_idx ON public.todos USING hash (b)
        #   CREATE INDEX todos_b_desc_idx ON public.todos USING btree (b DESC)
      RUBY

      assert_equal expected.gsub(/^/, "  "), body(columns, constraints:, indexes:)
    end

    it "comments every line of a definition that spans several, as SQLite keeps one written so, and as PostgreSQL " \
       "keeps a string holding a newline" do
      columns = [column(:a, "text"), column(:b, "text")]
      sqlite_body = body(
        columns,
        adapter: sqlite,
        constraints: [constraint(nil, :check, %i[a b], "CHECK (a IS NOT NULL\n    OR b IS NOT NULL)")],
        indexes: [index("todos_open", [:a], "CREATE INDEX todos_open ON todos (a)\n  WHERE b IS NULL")]
      )
      postgresql_body = body(
        columns,
        constraints: [constraint("todos_check", :check, %i[a b], "CHECK (((a <> 'x\ny'::text) OR (b IS NULL)))")],
        indexes: [
          index(
            "todos_expr_idx",
            [],
            "CREATE INDEX todos_expr_idx ON public.todos USING btree ((((a || '\n'::text) || b)))"
          )
        ]
      )
      expected = [<<~RUBY.chomp, <<~RUBY.chomp].map { |lines| lines.gsub(/^/, "  ") }
        # `skyward migration` will drop these, since a table class can't declare them:
        #   CHECK (a IS NOT NULL
        #       OR b IS NOT NULL)
        #   CREATE INDEX todos_open ON todos (a)
        #     WHERE b IS NULL
      RUBY
        # `skyward migration` will drop these, since a table class can't declare them:
        #   CONSTRAINT todos_check CHECK (((a <> 'x
        #   y'::text) OR (b IS NULL)))
        #   CREATE INDEX todos_expr_idx ON public.todos USING btree ((((a || '
        #   '::text) || b)))
      RUBY

      assert_equal expected, [sqlite_body, postgresql_body]
    end

    it "comments on a foreign key to a table it isn't given, as one the class can't declare" do
      reference = constraint(
        "todos_a_fkey",
        :foreign_key,
        [:a],
        "FOREIGN KEY (a) REFERENCES users(id)",
        references: :users
      )
      expected = <<~RUBY.chomp
        # `skyward migration` will drop these, since a table class can't declare them:
        #   CONSTRAINT todos_a_fkey FOREIGN KEY (a) REFERENCES users(id)
      RUBY

      assert_equal expected.gsub(/^/, "  "), body([column(:a, "bigint")], constraints: [reference])
    end

    it "declares a primary key other than id" do
      todos = table(:todos, [column(:code, "text")], key: :code)

      assert_includes source.text(todos, [todos], postgresql, []), "  table :todos\n  primary_key :code\n"
    end

    it "declares a reference with no on_delete: for NO ACTION, or none" do
      constraints = [
        constraint(
          "todos_a_fkey",
          :foreign_key,
          [:a],
          "FOREIGN KEY (a) REFERENCES lists(id) ON DELETE NO ACTION",
          references: :lists
        ),
        constraint("todos_b_fkey", :foreign_key, [:b], "FOREIGN KEY (b) REFERENCES lists", references: :lists)
      ]

      assert_equal "  references :a, MigrationsFixtures::List\n  references :b, MigrationsFixtures::List",
                   body([column(:a, "bigint"), column(:b, "bigint")], constraints:, classes: [MigrationsFixtures::List])
    end

    it "reads on_delete: from ON DELETE" do
      constraints = ["RESTRICT", "SET NULL", "SET DEFAULT"].map do |action|
        constraint(
          "todos_a_fkey",
          :foreign_key,
          [:a],
          "FOREIGN KEY (a) REFERENCES lists(id) ON DELETE #{action}",
          references: :lists
        )
      end
      declared = constraints.map do |reference|
        body([column(:a, "bigint")], constraints: [reference], classes: [MigrationsFixtures::List])
      end

      expected = %w[restrict set_null set_default].map do |action|
        "  references :a, MigrationsFixtures::List, on_delete: :#{action}"
      end

      assert_equal expected, declared
    end

    it "names a table no loaded class declares as scaffold would, and says to scaffold it too" do
      reference = constraint("todos_a_fkey", :foreign_key, [:a], "FOREIGN KEY (a) REFERENCES lists", references: :lists)

      assert_equal "  # lists has no class yet. Scaffold it too: skyward scaffold lists\n  references :a, List",
                   body([column(:a, "bigint")], constraints: [reference])
    end

    it "names the class itself for a reference to its own table" do
      reference = constraint(
        "todos_a_fkey",
        :foreign_key,
        [:a],
        "FOREIGN KEY (a) REFERENCES todos(id)",
        references: :todos
      )

      assert_equal "  references :a, Todo", body([column(:a, "bigint")], constraints: [reference])
    end

    it "declares a unique constraint, and a unique index as one, saying skyward migration will replace it" do
      columns = [column(:a, "text"), column(:b, "text")]
      constraints = [constraint("todos_a_b_key", :unique, %i[a b], "UNIQUE (a, b)")]
      indexes = [index("todos_b", [:b], 'CREATE UNIQUE INDEX todos_b ON todos ("b")', unique: true)]
      expected = <<~RUBY.chomp
        unique :a, :b
        # `skyward migration` will replace the unique index todos_b with a constraint on the same columns.
        unique :b
      RUBY

      assert_equal expected.gsub(/^/, "  "), body(columns, adapter: sqlite, constraints:, indexes:)
    end

    it "comments every line of a unique index's name that holds a newline" do
      indexes = [index(
        "todos\nb",
        [:b],
        %(CREATE UNIQUE INDEX "todos\nb" ON public.todos USING btree (b)),
        unique: true
      )]
      expected = <<~RUBY.chomp
        # `skyward migration` will replace the unique index todos
        # b with a constraint on the same columns.
        unique :b
      RUBY

      assert_equal expected.gsub(/^/, "  "), body([column(:b, "text")], indexes:)
    end

    it "declares a check on one column, holding its expression, and an index on columns" do
      constraints = [constraint(nil, :check, [:a], "CHECK (length(a) BETWEEN 1 AND 200)")]
      indexes = [index("todos_a", [:a], "CREATE INDEX todos_a ON todos(a)")]

      assert_equal "  check :a, Skyward.sql(\"length(a) BETWEEN 1 AND 200\")\n  index :a",
                   body([column(:a, "TEXT")], adapter: sqlite, constraints:, indexes:)
    end

    it "aligns each reader's type, and starts each type the database has no column type for with a comment" do
      expected = [
        "  attr_reader :id     #: Integer\n",
        "  # total is bytea, which has no column type, so it's untyped.\n",
        "  attr_reader :total  #: untyped\n",
        "  # meta is jsonb, which has no column type, so it's untyped.\n",
        "  attr_reader :meta   #: untyped\n"
      ]

      assert_equal expected, readers([column(:total, "bytea"), column(:meta, "jsonb", nullable: true)])
    end

    it "says a column SQLite declares with no type has none, and comments every line of a type that spans several" do
      expected = [
        "  # x has no SQL type, so it's untyped.\n",
        "  attr_reader :x   #: untyped\n",
        "  # y is FOO(\n",
        "  # 1), which has no column type, so it's untyped.\n",
        "  attr_reader :y   #: untyped\n"
      ]

      assert_equal expected, readers([column(:x, ""), column(:y, "FOO(\n1)")], adapter: sqlite).drop(1)
    end

    it "types each column the adapter reads, nullable or not" do
      columns = [column(:a, "BOOLEAN", nullable: true), column(:b, "DATE"), column(:c, "DATETIME(6)", nullable: true)]

      expected = ["  attr_reader :id  #: Integer\n", "  attr_reader :a   #: bool?\n", "  attr_reader :b   #: Date\n",
                  "  attr_reader :c   #: Time?\n"]

      assert_equal expected, readers(columns, adapter: sqlite)
    end

    it "types a text column with a check that lists only strings as a symbol union, as SQLite keeps it, and " \
       "leaves the check to the type" do
      columns = [column(:status, "TEXT", nullable: true)]
      constraints = [constraint(nil, :check, [:status], "CHECK (status IN ('to do', 'it''s done'))")]

      assert_equal [%(  attr_reader :status  #: (:"to do" | :"it's done")?\n), nil],
                   [readers(columns, adapter: sqlite, constraints:).last, body(columns, adapter: sqlite, constraints:)]
    end

    it "types a varchar column with a check that lists only strings as a symbol union, as PostgreSQL rewrites it" do
      check = "CHECK (((kind)::text = ANY ((ARRAY['a'::character varying, 'b'::character varying])::text[])))"
      constraints = [constraint("todos_kind_check", :check, [:kind], check)]

      assert_equal "  attr_reader :kind  #: :a | :b\n",
                   readers([column(:kind, "character varying(10)")], constraints:).last
    end

    it "keeps as a check one that lists more than strings, or is on a column that isn't text" do
      constraints = [
        constraint("todos_a_check", :check, [:a], "CHECK ((a = ANY (ARRAY['x'::text, NULL::text])) OR (a IS NULL))"),
        constraint("todos_b_check", :check, [:b], "CHECK ((b = ANY (ARRAY['x'::citext])))")
      ]

      expected = <<~RUBY.chomp
        check :a, Skyward.sql("(a = ANY (ARRAY['x'::text, NULL::text])) OR (a IS NULL)")
        check :b, Skyward.sql("(b = ANY (ARRAY['x'::citext]))")
      RUBY

      assert_equal expected.gsub(/^/, "  "), body([column(:a, "text"), column(:b, "citext")], constraints:)
    end

    it "writes no default for NULL" do
      assert_nil body([column(:a, "text", nullable: true, default: "NULL")])
    end

    it "writes a literal default as the value the column's type reads" do
      defaults = [
        ["bigint", "-1"], ["double precision", "1.5"], ["real", "0"], ["text", "'it''s'"], ["uuid", "'x'"],
        ["boolean", "true"], ["date", "'2026-01-01'"], ["jsonb", "'{}'"]
      ].map { |type, default| default(type, default) }

      assert_equal ["-1", "1.5", "0", %("it's"), %("x"), "true", "Date.new(2026, 1, 1)", %("{}")], defaults
    end

    it "reads SQLite's 0 and 1 as a bool's false and true" do
      assert_equal(%w[false true], %w[0 1].map { |default| default("BOOLEAN", default, adapter: sqlite) })
    end

    it "writes a time SQLite keeps as its adapter encodes one as a Time" do
      defaults = ["'2026-01-02 03:04:05.000000'", "'2026-01-02 03:04:05.123456'"].map do |default|
        default("DATETIME", default, adapter: sqlite)
      end

      assert_equal ["Time.utc(2026, 1, 2, 3, 4, 5)", "Time.utc(2026, 1, 2, 3, 4, 5, 123456)"], defaults
    end

    it "writes a symbol union's default as a Symbol" do
      check = constraint(nil, :check, [:a], "CHECK (a IN ('low', 'high'))")

      assert_includes body([column(:a, "TEXT", default: "'low'")], adapter: sqlite, constraints: [check]),
                      "  default a: :low"
    end

    it "writes any other default as SQL, without the parentheses SQLite's adapter puts back" do
      defaults = [
        ["timestamp with time zone", "now()", postgresql], ["integer", "nextval('todos_id_seq'::regclass)", postgresql],
        ["numeric(10,2)", "1.10", postgresql], ["date", "CURRENT_DATE", postgresql],
        ["date", "'2026-02-30'", postgresql], ["boolean", "'t'", postgresql],
        ["DATETIME", "(CURRENT_TIMESTAMP)", sqlite], ["TEXT", "('a' || 'b')", sqlite]
      ].map { |type, default, adapter| default(type, default, adapter:) }
      expected = [
        'Skyward.sql("now()")', %(Skyward.sql("nextval('todos_id_seq'::regclass)")), 'Skyward.sql("1.10")',
        'Skyward.sql("CURRENT_DATE")', %(Skyward.sql("'2026-02-30'")), %(Skyward.sql("'t'")),
        'Skyward.sql("CURRENT_TIMESTAMP")', %(Skyward.sql("'a' || 'b'"))
      ]

      assert_equal expected, defaults
    end

    it "writes a literal SQLite keeps that no value writes back the same as the value it reads as, saying " \
       "skyward migration will rewrite it once" do
      columns = [
        column(:a, "NUMERIC", default: "1.50"),
        column(:b, "BOOLEAN", default: "TRUE"),
        column(:c, "DATETIME", default: "'2026-01-02 03:04:05'"),
        column(:d, "INTEGER", default: "010"),
        column(:e, "TEXT", default: "'x'")
      ]
      expected = <<~RUBY.chomp
        # `skyward migration` will rewrite these defaults once, as the values below, since SQLite keeps each as it was written: a, b, c, d
        default a: 1.5, b: true, c: Time.utc(2026, 1, 2, 3, 4, 5), d: 10, e: "x"
      RUBY

      assert_equal expected.gsub(/^/, "  "), body(columns, adapter: sqlite)
    end

    it "comments on a literal SQLite keeps that no value of its column's type reads, as what skyward migration " \
       "will drop" do
      columns = [
        column(:a, "DATETIME", default: "'2026-02-30 03:04:05.000000'"),
        column(:b, "INTEGER", default: "'x'"),
        column(:c, "TEXT", default: "'x'")
      ]
      expected = <<~RUBY.chomp
        # `skyward migration` will drop these, since a table class can't declare them:
        #   a DEFAULT '2026-02-30 03:04:05.000000'
        #   b DEFAULT 'x'
        default c: "x"
      RUBY

      assert_equal expected.gsub(/^/, "  "), body(columns, adapter: sqlite)
    end
  end

  describe ".class_name" do
    it "camel-cases the table's name, dropping a trailing s, ies for y and sses for ss, and keeping ss" do
      names = %i[todos order_items categories addresses glass].map { |table| source.class_name(table) }

      assert_equal %w[Todo OrderItem Category Address Glass], names
    end
  end
end
