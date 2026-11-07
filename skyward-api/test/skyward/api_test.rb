# frozen_string_literal: true

require "test_helper"

describe Skyward::API do
  it "loads every file under its own part of the Skyward namespace" do
    # Eager loading raises if any file's name doesn't match its constant.
    Zeitwerk::Loader.eager_load_all

    assert_includes Zeitwerk::Loader.all_dirs, File.expand_path("../../lib/skyward", __dir__)
  end

  it "gives every API class the route declarations" do
    assert_kind_of Skyward::API::Declarations, Skyward::API
  end
end
