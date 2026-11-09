# frozen_string_literal: true

module Skyward::ORM::Migrations::Discovery
  extend self

  # Subclasses lists only loaded classes, so an app that autoloads would
  # otherwise hide every table class nothing has used yet.
  # @rbs loader: singleton(Zeitwerk::Loader)
  # @rbs return: Array[singleton(Skyward::ORM::Record)]
  def table_classes(loader)
    loader.eager_load_all
    Skyward::ORM::Tables::Loaded.table_classes(Skyward::ORM::Record)
  end
end
