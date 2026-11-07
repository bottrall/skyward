# frozen_string_literal: true

require "test_helper"

describe Skyward::Signatures::Loader do
  fixtures = File.expand_path("../../fixtures/signatures", __dir__)
  app = File.join(fixtures, "app")
  gem_sig = File.join(fixtures, "gem")
  gem_id = RBS::TypeName.parse("::gem_id")

  let(:loader) { Skyward::Signatures::Loader.new }

  describe "#register" do
    it "adds a gem's signatures to every load" do
      loader.register(gem_sig)

      assert loader.load(app).env.type_alias_name?(gem_id)
    end

    it "ignores a path it already has, however it's spelled" do
      # Loading the gem's sig/ twice would declare gem_id twice, which raises.
      loader.register(gem_sig)
      loader.register(File.join(gem_sig, "..", "gem"))

      assert loader.load(app).env.type_alias_name?(gem_id)
    end
  end

  describe "#load" do
    it "loads every .rbs file under the directory, however deep" do
      env = loader.load(app).env

      assert(%w[::Todo ::NewTodo].all? { |name| env.class_decl?(RBS::TypeName.parse(name)) })
    end

    it "accepts a directory that doesn't exist" do
      assert_instance_of RBS::DefinitionBuilder, loader.load(File.join(fixtures, "missing"))
    end

    it "leaves out a gem that hasn't registered" do
      refute loader.load(app).env.type_alias_name?(gem_id)
    end

    it "includes the date library" do
      assert loader.load(app).env.class_decl?(RBS::TypeName.parse("::Date"))
    end

    it "includes the time library" do
      assert_includes loader.load(app).build_singleton(RBS::TypeName.parse("::Time")).methods, :parse
    end

    it "raises BootError naming the file and line that doesn't parse" do
      error = assert_raises(Skyward::BootError) { loader.load(File.join(fixtures, "broken")) }

      assert_match %r{#{Regexp.escape(fixtures)}/broken/broken\.rbs:3:.*Syntax error}, error.message
    end

    it "raises BootError naming every file and line of a duplicated declaration" do
      error = assert_raises(Skyward::BootError) { loader.load(File.join(fixtures, "duplicated")) }

      %w[a b].each { |file| assert_includes error.message, "#{fixtures}/duplicated/#{file}.rbs:1:" }
    end

    it "raises BootError naming the file and line of mismatched generic parameters" do
      error = assert_raises(Skyward::BootError) { loader.load(File.join(fixtures, "generic")) }

      assert_match %r{#{Regexp.escape(fixtures)}/generic/\w\.rbs:1:.*Generic parameters mismatch: ::Box}, error.message
    end

    it "builds a fresh environment on every call" do
      refute_same loader.load(app).env, loader.load(app).env
    end
  end
end
