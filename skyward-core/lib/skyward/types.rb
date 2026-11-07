# frozen_string_literal: true

module Skyward::Types
  # @rbs!
  #   type scalar = :integer | :float | :string | :bool | :date | :time | :untyped
  #   type literal = String | Integer | bool | nil
  #   type t = Scalar | Literal | Enum | Nullable | ArrayOf | Record | Named | Union
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

  Unreadable = Data.define(
    :type, #: String
    :at, #: String?
    :instead #: String
  )
end
