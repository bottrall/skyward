# frozen_string_literal: true

require "test_helper"

describe Skyward::Signatures do
  it "loads through the process's one loader" do
    assert_instance_of RBS::DefinitionBuilder, Skyward::Signatures.load(File.expand_path("missing", __dir__))
  end
end
