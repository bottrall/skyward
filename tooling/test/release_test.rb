# frozen_string_literal: true

require 'test_helper'
require 'release'

describe Release do
  let(:source) { "module Skyward\n  VERSION = '0.1.0' #: String\nend\n" }

  describe '.version' do
    it 'reads the version from a version.rb' do
      assert_equal '0.1.0', Release.version(source)
    end

    it 'reads a double-quoted version' do
      assert_equal '0.1.0', Release.version(source.tr("'", '"'))
    end

    it 'returns nil for a file with no version' do
      assert_nil Release.version("module Skyward\nend\n")
    end
  end

  describe '.shared' do
    it 'returns the version every source agrees on' do
      assert_equal '0.1.0', Release.shared([source, source])
    end

    it 'returns nil when the sources disagree' do
      assert_nil Release.shared([source, source.sub('0.1.0', '0.2.0')])
    end

    it "reads one version from every gem's version.rb" do
      root = File.expand_path('../..', __dir__)
      sources = Release::VERSION_FILES.map { |file| File.read(File.join(root, file)) }

      assert_match(/\A\d+\.\d+\.\d+/, Release.shared(sources))
    end
  end
end
