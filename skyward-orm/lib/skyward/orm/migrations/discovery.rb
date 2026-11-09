# frozen_string_literal: true

module Skyward::ORM::Migrations::Discovery
  extend self

  # Subclasses lists only loaded classes, so an app that autoloads would
  # otherwise hide every table class nothing has used yet.
  # @rbs loader: singleton(Zeitwerk::Loader)
  # @rbs return: Array[singleton(Skyward::ORM::Record)]
  def table_classes(loader)
    loader.eager_load_all
    descendants(Skyward::ORM::Record).select { |klass| klass.schema.table }
  end

  private

  # @rbs klass: singleton(Skyward::ORM::Record)
  # @rbs return: Array[singleton(Skyward::ORM::Record)]
  def descendants(klass)
    subclasses = klass.subclasses #: Array[singleton(Skyward::ORM::Record)]
    subclasses.flat_map { |subclass| [subclass, *descendants(subclass)] }
  end
end
