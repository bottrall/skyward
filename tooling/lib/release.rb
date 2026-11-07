# frozen_string_literal: true

# The Skyward gems release in lockstep, so the version in each gem's
# version.rb is always the same. release-please bumps them all together.
module Release
  extend self

  VERSION_FILES = %w[
    skyward-core/lib/skyward/core/version.rb
    skyward-api/lib/skyward/api/version.rb
    skyward-orm/lib/skyward/orm/version.rb
    skyward/lib/skyward/version.rb
  ].freeze

  ASSIGNMENT = /VERSION = "([^"]*)"/

  def version(source) = source[ASSIGNMENT, 1]

  # The version every source agrees on, or nil when they disagree.
  def shared(sources)
    versions = sources.map { |source| version(source) }.uniq
    versions.first if versions.size == 1
  end
end
