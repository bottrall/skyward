# frozen_string_literal: true

require "test_helper"
require_relative "../../../fixtures/tables/tables_fixtures"

describe Skyward::ORM::Tables::Validation do
  def refusal(klass)
    assert_raises(Skyward::Core::BootError) { Skyward::ORM::Tables::Validation.validate(klass) }.message
  end

  describe ".validate" do
    it "passes a class whose declarations name its columns" do
      assert_nil Skyward::ORM::Tables::Validation.validate(TablesFixtures::Todo)
    end

    it "checks the default primary key, id" do
      assert_equal "#{TablesFixtures::Literal} has no column id, which its primary_key names. " \
                   "Add `attr_reader :id`, or fix the name.",
                   refusal(TablesFixtures::Literal)
    end

    it "names the class and each column a declaration names that it doesn't have" do
      klass = Class.new(Skyward::ORM::Record) do
        primary_key :code
        references :list_id, TablesFixtures::List
        default done: false
        unique :email
        check :title, length: 1..200
        index :list_id, :due_on
        attr_reader :code, :title
      end
      expected = [
        "#{klass} has no column list_id, which its references names. Add `attr_reader :list_id`, or fix the name.",
        "#{klass} has no column done, which its default names. Add `attr_reader :done`, or fix the name.",
        "#{klass} has no column email, which its unique names. Add `attr_reader :email`, or fix the name.",
        "#{klass} has no column list_id, which its index names. Add `attr_reader :list_id`, or fix the name.",
        "#{klass} has no column due_on, which its index names. Add `attr_reader :due_on`, or fix the name."
      ]

      assert_equal expected.join("\n"), refusal(klass)
    end

    it "checks a check's column" do
      klass = Class.new(Skyward::ORM::Record) do
        check :title, length: 1..200
        attr_reader :id
      end

      assert_equal "#{klass} has no column title, which its check names. Add `attr_reader :title`, or fix the name.",
                   refusal(klass)
    end

    it "names a column once for each declaration that names it" do
      klass = Class.new(Skyward::ORM::Record) do
        index :done
        index :done
        attr_reader :id
      end

      assert_equal "#{klass} has no column done, which its index names. Add `attr_reader :done`, or fix the name.",
                   refusal(klass)
    end
  end
end
