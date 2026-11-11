# frozen_string_literal: true

require "test_helper"

describe Skyward::ORM::Statements::Placeholders do
  def numbered(sql, count) = Skyward::ORM::Statements::Placeholders.replace(sql, count) { |position| "$#{position}" }

  describe ".replace" do
    it "replaces each ? with the placeholder for its position, from 1" do
      assert_equal "SELECT * FROM todos WHERE list_id = $1 AND title = $2",
                   numbered("SELECT * FROM todos WHERE list_id = ? AND title = ?", 2)
    end

    it "leaves SQL with no ? as it is" do
      assert_equal "SELECT 1", numbered("SELECT 1", 0)
    end

    it "keeps a ? in a string" do
      assert_equal "SELECT 'why?', 'it''s?' WHERE id = $1", numbered("SELECT 'why?', 'it''s?' WHERE id = ?", 1)
    end

    it "keeps a ? in a quoted name" do
      assert_equal 'SELECT "done?" FROM todos WHERE id = $1', numbered('SELECT "done?" FROM todos WHERE id = ?', 1)
    end

    it "keeps a ? in a line comment" do
      assert_equal "SELECT $1 -- why?\nFROM todos", numbered("SELECT ? -- why?\nFROM todos", 1)
    end

    it "keeps a ? in a block comment, across lines" do
      assert_equal "SELECT /* why?\nhow? */ $1", numbered("SELECT /* why?\nhow? */ ?", 1)
    end

    it "refuses fewer values than ?" do
      error = assert_raises(ArgumentError) { numbered("SELECT ?, ?", 1) }

      assert_equal "The SQL has 2 ?, each taking one value, but was given 1", error.message
    end

    it "refuses more values than ?" do
      error = assert_raises(ArgumentError) { numbered("SELECT 'why?'", 1) }

      assert_equal "The SQL has 0 ?, each taking one value, but was given 1", error.message
    end
  end

  describe ".require_scalars" do
    it "passes scalars" do
      assert_silent { Skyward::ORM::Statements::Placeholders.require_scalars([1, "a", nil], "The SQL") }
    end

    it "refuses an Array, naming its position" do
      error = assert_raises(ArgumentError) { Skyward::ORM::Statements::Placeholders.require_scalars([1, [2, 3]], "The SQL") }

      assert_equal "The SQL binds one value to each ?, but value 2 is an Array", error.message
    end

    it "refuses a Hash, naming its position" do
      error = assert_raises(ArgumentError) { Skyward::ORM::Statements::Placeholders.require_scalars([{ a: 1 }], "The SQL") }

      assert_equal "The SQL binds one value to each ?, but value 1 is a Hash", error.message
    end
  end
end
