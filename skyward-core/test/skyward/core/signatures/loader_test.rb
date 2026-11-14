# frozen_string_literal: true

require 'test_helper'

describe Skyward::Core::Signatures::Loader do
  fixtures = File.expand_path('../../../fixtures/signatures', __dir__)
  app = File.join(fixtures, 'app')
  gem_sig = File.join(fixtures, 'gem')
  gem_id = RBS::TypeName.parse('::gem_id')
  relative = fixtures.delete_prefix("#{Dir.pwd}/")

  let(:loader) { Skyward::Core::Signatures::Loader.new }

  describe '#register' do
    it "adds a gem's signatures to every load" do
      loader.register(gem_sig)

      assert loader.load(app).env.type_alias_name?(gem_id)
    end

    it "ignores a path it already has, however it's spelled" do
      # Loading the gem's sig/ twice would declare gem_id twice, which raises.
      loader.register(gem_sig)
      loader.register(File.join(gem_sig, '..', 'gem'))

      assert loader.load(app).env.type_alias_name?(gem_id)
    end
  end

  describe '#load' do
    it 'loads every .rbs file under the directory, however deep' do
      env = loader.load(app).env

      assert(%w[::Todo ::NewTodo].all? { |name| env.class_decl?(RBS::TypeName.parse(name)) })
    end

    it "accepts a directory that doesn't exist" do
      assert_instance_of RBS::DefinitionBuilder, loader.load(File.join(fixtures, 'missing'))
    end

    it "leaves out a gem that hasn't registered" do
      refute loader.load(app).env.type_alias_name?(gem_id)
    end

    it 'includes the date library' do
      assert loader.load(app).env.class_decl?(RBS::TypeName.parse('::Date'))
    end

    it 'includes the time library' do
      assert_includes loader.load(app).build_singleton(RBS::TypeName.parse('::Time')).methods, :parse
    end

    it 'includes the bigdecimal library' do
      assert loader.load(app).env.class_decl?(RBS::TypeName.parse('::BigDecimal'))
    end

    it "raises BootError with an excerpt under the token that doesn't parse" do
      error = assert_raises(Skyward::Core::BootError) { loader.load(File.join(fixtures, 'broken')) }

      assert_equal <<~MESSAGE.chomp, error.message
        Can't load the RBS signatures: Syntax error: unexpected token for simple type.

            #{relative}/broken/broken.rbs:3
            end
            ^^^
      MESSAGE
    end

    it 'raises BootError with an excerpt under each name of a duplicated declaration' do
      error = assert_raises(Skyward::Core::BootError) { loader.load(File.join(fixtures, 'duplicated')) }

      assert_equal <<~MESSAGE.chomp, error.message
        Can't load the RBS signatures: id is declared twice.

            #{relative}/duplicated/b.rbs:1
            type id = String
                 ^^

            #{relative}/duplicated/a.rbs:1
            type id = Integer
                 ^^
      MESSAGE
    end

    it 'raises BootError with an excerpt under the new name of a duplicated class alias' do
      error = assert_raises(Skyward::Core::BootError) { loader.load(File.join(fixtures, 'duplicated_alias')) }

      assert_equal <<~MESSAGE.chomp, error.message
        Can't load the RBS signatures: Foo is declared twice.

            #{relative}/duplicated_alias/foo.rbs:1
            class Foo = String
                  ^^^
            ...
            class Foo
                  ^^^
      MESSAGE
    end

    it 'raises BootError with an excerpt under the declaration whose generic parameters mismatch' do
      error = assert_raises(Skyward::Core::BootError) { loader.load(File.join(fixtures, 'generic')) }

      assert_equal <<~MESSAGE.chomp, error.message
        Can't load the RBS signatures: Generic parameters mismatch: ::Box

            #{relative}/generic/b.rbs:1
            class Box[T, U]
                  ^^^
      MESSAGE
    end

    it 'builds a fresh environment on every call' do
      refute_same loader.load(app).env, loader.load(app).env
    end
  end
end
