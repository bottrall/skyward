# frozen_string_literal: true

# Ruby run with --disable-did_you_mean doesn't load it.
require 'did_you_mean'

module Skyward::Core::Diagnostics::Suggestion
  extend self

  # @rbs name: String
  # @rbs names: Array[String]
  # @rbs return: String?
  def closest(name, names) = DidYouMean::SpellChecker.new(dictionary: names).correct(name).first
end
