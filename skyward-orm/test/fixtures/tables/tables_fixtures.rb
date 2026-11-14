# frozen_string_literal: true

require 'date'

module TablesFixtures
  class List < Skyward::ORM::Record
    table :lists

    attr_reader :id, :name
  end

  # The README's Todo, from Tables.
  class Todo < Skyward::ORM::Record
    table :todos
    references :list_id, List, on_delete: :cascade
    default priority: :normal, done: false, created_at: Skyward.sql('now()')
    check :title, length: 1..200
    index :list_id, :done

    attr_reader :id, :list_id, :title, :priority, :due_on, :done, :created_at

    def overdue?(today = Date.today) = !done && !due_on.nil? && due_on < today
  end

  # A JSON column, and a nullable one.
  class Webhook < Skyward::ORM::Record
    table :webhooks

    attr_reader :id, :settings, :payload
  end

  # search is a column the database generates.
  class Searched < Skyward::ORM::Record
    table :searches

    attr_reader :id, :title, :search
  end

  # The README's BigDecimal column, and a nullable one.
  class Product < Skyward::ORM::Record
    table :products

    attr_reader :id, :price, :discount
  end

  # An Array column of each element type, and a nullable one.
  class Arrayed < Skyward::ORM::Record
    table :arrays

    attr_reader :id, :integers, :floats, :decimals, :strings, :bools, :dates, :times, :weekdays, :tags
  end

  class Typed < Skyward::ORM::Record
    attr_reader :integer,
                :float,
                :string,
                :bool,
                :date,
                :time,
                :enum,
                :optional,
                :or_nil,
                :aliased,
                :nullable_enum,
                :decimal,
                :nullable_decimal,
                :json,
                :nullable_json,
                :untyped,
                :unannotated
  end

  # Each of these has one column whose type isn't a column type.
  class Tuple < Skyward::ORM::Record
    attr_reader :tags
  end

  class Holder < Skyward::ORM::Record
    attr_reader :pair
  end

  class Nested < Skyward::ORM::Record
    attr_reader :node
  end

  class Listed < Skyward::ORM::Record
    attr_reader :tags
  end

  class Grid < Skyward::ORM::Record
    attr_reader :rows
  end

  class Loose < Skyward::ORM::Record
    attr_reader :items
  end

  class Documented < Skyward::ORM::Record
    attr_reader :documents
  end

  class Plotted < Skyward::ORM::Record
    attr_reader :coordinates
  end

  class Grouped < Skyward::ORM::Record
    attr_reader :lists
  end

  class Recorded < Skyward::ORM::Record
    attr_reader :point
  end

  class Classed < Skyward::ORM::Record
    attr_reader :list
  end

  class Hashed < Skyward::ORM::Record
    attr_reader :settings
  end

  class Mixed < Skyward::ORM::Record
    attr_reader :value
  end

  class Literal < Skyward::ORM::Record
    attr_reader :kind
  end

  # Their types are in #: comments, as rbs-inline reads them.
  class Annotated < Skyward::ORM::Record
    attr_reader :tags #: Array[String]
  end

  # Memo's reader misspells String.
  class Misnamed < Skyward::ORM::Record
    attr_reader :memo #: Memo
  end

  # Each declaration names a column the class doesn't have, most of them misspelt.
  class Misspelt < Skyward::ORM::Record
    primary_key :cdoe
    references :lsit_id, List
    default dnoe: false
    unique :emial
    check :titel, length: 1..200
    index :lsit_id, :due_on

    attr_reader :code, :list_id, :title, :done, :email
  end

  # Its column is close to id, the default primary key it doesn't have.
  class Keyless < Skyward::ORM::Record
    attr_reader :ids
  end

  Pair = Class.new
  Node = Class.new
  Memo = Class.new

  # Its columns are typed with Skyward ORM's aliases.
  class Refined < Skyward::ORM::Record
    attr_reader :id, :logins, :rank, :invited_by
  end

  # Its column is an Array of one of Skyward ORM's aliases.
  class Identified < Skyward::ORM::Record
    attr_reader :ids
  end

  # Unsigned has no RBS declaration.
  class Unsigned < Skyward::ORM::Record
    attr_reader :id
  end

  # The README's Overdue, from Raw SQL.
  Overdue = Data.define(:title, :days_late)

  # Due's note is untyped.
  Due = Data.define(:title, :due_on, :note)

  # The README's TodoTitle, TodoWithList and OpenCount, from Projections, joins
  # and aggregates.
  TodoTitle = Data.define(:id, :title)
  TodoWithList = Data.define(:id, :title, :list_name)
  OpenCount = Data.define(:list_id, :open)

  # Labelled types priority unlike Todo's column, and Todo has no column
  # finished.
  Labelled = Data.define(:priority)
  Progress = Data.define(:list_id, :finished)
end
