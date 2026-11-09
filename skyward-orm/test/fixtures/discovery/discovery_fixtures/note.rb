# frozen_string_literal: true

class DiscoveryFixtures::Note < Skyward::ORM::Record
  table :notes

  attr_reader :id
end
