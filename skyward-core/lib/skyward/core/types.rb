# frozen_string_literal: true

module Skyward::Core::Types
  # @rbs!
  #   type scalar = :integer | :float | :string | :bool | :date | :time | :decimal | :untyped
  #   type literal = String | Integer | bool | nil
  #   type t = Scalar | Literal | Enum | Nullable | ArrayOf | HashOf | Record | Named | Union | Refined
  #   type result = t | Unreadable

  Scalar = Data.define(
    :name #: scalar
  )

  Literal = Data.define(
    :value #: literal
  )

  Enum = Data.define(
    :symbols #: Array[Symbol]
  )

  Nullable = Data.define(
    :type #: t
  )

  ArrayOf = Data.define(
    :type #: t
  )

  HashOf = Data.define(
    :type #: t
  )

  Field = Data.define(
    :name, #: Symbol
    :type, #: t
    :required #: bool
  )

  Record = Data.define(
    :fields #: Array[Field]
  )

  Named = Data.define(
    :name, #: String
    :klass, #: Class
    :fields #: Array[Field]
  )

  Union = Data.define(
    :types #: Array[t]
  )

  Refined = Data.define(
    :type, #: t
    :as #: Symbol
  )

  Unreadable = Data.define(
    :type, #: String
    :at, #: String?
    :instead, #: String
    :suggestion #: String?
  )
end
