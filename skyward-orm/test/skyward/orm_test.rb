# frozen_string_literal: true

require "test_helper"

describe Skyward::ORM do
  it "loads every file under its own part of the Skyward namespace" do
    # Eager loading raises if any file's name doesn't match its constant.
    Zeitwerk::Loader.eager_load_all

    assert_includes Zeitwerk::Loader.all_dirs, File.expand_path("../../lib/skyward", __dir__)
  end

  it "registers its signatures, which an app's table classes subclass" do
    builder = Skyward::Core::Signatures.load(File.expand_path("missing", __dir__))

    assert builder.env.class_decl?(RBS::TypeName.parse("::Skyward::ORM::Record"))
  end
end

describe Skyward do
  describe ".sql" do
    it "wraps an SQL expression" do
      assert_equal Skyward::ORM::Tables::SQL.new(expression: "now()"), Skyward.sql("now()")
    end

    it "keeps a frozen copy" do
      assert_predicate Skyward.sql(+"now()").expression, :frozen?
    end

    it "refuses anything but a String" do
      error = assert_raises(ArgumentError) { Skyward.sql(:now) }

      assert_equal "Skyward.sql takes the SQL as a String, not :now", error.message
    end
  end
end
