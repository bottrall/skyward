# frozen_string_literal: true

# rubocop:disable-next Local/NoInheritance -- discovery must find a table class below one that isn't a direct subclass
class DiscoveryFixtures::Note < DiscoveryFixtures::Base
  table :notes

  attr_reader :id
end
