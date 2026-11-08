# frozen_string_literal: true

require "test_helper"

describe Skyward::Core::Signatures do
  it "loads through the process's one loader" do
    assert_instance_of RBS::DefinitionBuilder, Skyward::Core::Signatures.load(File.expand_path("missing", __dir__))
  end
end
