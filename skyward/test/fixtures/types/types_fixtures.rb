# frozen_string_literal: true

module TypesFixtures
  # A column of every type both gems read, and a nullable one of each.
  class Everything < Skyward::ORM::Record
    table :everythings

    attr_reader :id,
                :count,
                :ratio,
                :amount,
                :title,
                :done,
                :due_on,
                :due_at,
                :priority,
                :settings,
                :counts,
                :ratios,
                :amounts,
                :titles,
                :flags,
                :due_ons,
                :due_ats,
                :priorities,
                :nullable_count,
                :nullable_ratio,
                :nullable_amount,
                :nullable_title,
                :nullable_done,
                :nullable_due_on,
                :nullable_due_at,
                :nullable_priority,
                :nullable_settings,
                :nullable_titles
  end

  class EverythingAPI < Skyward::API
    get "/everythings/:id", to: :show
    post "/everythings", to: :receive

    def initialize(received:)
      super()
      @received = received
    end

    def show(id:) = Everything.find_by(id:) || not_found

    def receive(body:)
      @received.push(body)
      no_content
    end
  end

  # A column and a body whose signatures a test writes, one type at a time,
  # to find which gems read it.
  class Column < Skyward::ORM::Record
    attr_reader :value
  end

  class Body < Skyward::API
    post "/", to: :echo

    def echo(body:) = body
  end

  # Classes with typed readers, for the types that name one.
  Item = Data.define(:id)
  Tag = Data.define(:name)
end
