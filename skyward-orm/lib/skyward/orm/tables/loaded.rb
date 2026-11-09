# frozen_string_literal: true

module Skyward::ORM::Tables::Loaded
  extend self

  # A subclass with no table is a shared base class or a row class, not a table.
  # @rbs root: singleton(Skyward::ORM::Record)
  # @rbs return: Array[singleton(Skyward::ORM::Record)]
  def table_classes(root)
    descendants(root).select { |klass| klass.schema.table }.sort_by(&:to_s)
  end

  private

  # @rbs klass: singleton(Skyward::ORM::Record)
  # @rbs return: Array[singleton(Skyward::ORM::Record)]
  def descendants(klass)
    subclasses = klass.subclasses #: Array[singleton(Skyward::ORM::Record)]
    subclasses.flat_map { |subclass| [subclass, *descendants(subclass)] }
  end
end
