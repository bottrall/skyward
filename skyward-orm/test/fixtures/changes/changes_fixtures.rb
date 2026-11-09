# frozen_string_literal: true

# An items table, and each way its class can come to differ from it. Every
# variant declares table :items, so each is compared with the table Item makes.
module ChangesFixtures
  class Owner < Skyward::ORM::Record
    table :owners

    attr_reader :id, :name
  end

  # Defines a class on the items table, with Item's declarations unless the
  # block leaves one out.
  def self.item(owner: { on_delete: :cascade }, status: :open, title: true, code: [:code], index: [:owner_id], &extra)
    Class.new(Skyward::ORM::Record) do
      table :items
      references :owner_id, Owner, **owner
      default status: status
      check :title, length: 1..100 if title
      unique(*code)
      index(*index)
      class_eval(&extra) if extra
    end
  end

  COLUMNS = %i[id owner_id title code status note rank].freeze

  Item = item { attr_reader(*COLUMNS) }
  Dropped = item { attr_reader(*(COLUMNS - [:note])) }
  Renamed = item { attr_reader(*COLUMNS.map { |column| column == :note ? :remark : column }) }
  Added = item { attr_reader(*COLUMNS, :pinned) }
  Serialed = item do
    unique :serial
    attr_reader(*COLUMNS, :serial)
  end
  Stamped = item do
    default added_at: Skyward.sql("CURRENT_TIMESTAMP")
    attr_reader(*COLUMNS, :added_at)
  end
  Retyped = item { attr_reader(*COLUMNS) }
  Required = item { attr_reader(*COLUMNS) }
  Redefaulted = item(status: :closed) { attr_reader(*COLUMNS) }
  Unchecked = item(title: false) { attr_reader(*COLUMNS) }
  Checked = item do
    check :note, length: ..500
    attr_reader(*COLUMNS)
  end
  Paired = item(code: %i[owner_id code]) { attr_reader(*COLUMNS) }
  Reindexed = item(index: %i[owner_id status]) { attr_reader(*COLUMNS) }
  Restricted = item(owner: { on_delete: :restrict }) { attr_reader(*COLUMNS) }

  # Owner with a check, which SQLite can only add by rebuilding the table
  # every item references.
  class CheckedOwner < Skyward::ORM::Record
    table :owners
    check :name, length: (1..)

    attr_reader :id, :name
  end
end
