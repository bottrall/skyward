# frozen_string_literal: true

require "test_helper"

describe Skyward::Core do
  it "loads every file under its own part of the Skyward namespace" do
    # Eager loading raises if any file's name doesn't match its constant.
    Zeitwerk::Loader.eager_load_all

    assert_includes Zeitwerk::Loader.all_dirs, File.expand_path("../../lib/skyward", __dir__)
  end

  it "registers its own signatures" do
    builder = Skyward::Signatures.load(File.expand_path("missing", __dir__))

    assert builder.env.class_decl?(RBS::TypeName.parse("::Skyward::BootError"))
  end
end
