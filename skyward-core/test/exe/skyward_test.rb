# frozen_string_literal: true

require "test_helper"
require "open3"

describe "exe/skyward" do
  def skyward(*args)
    exe = File.expand_path("../../exe/skyward", __dir__)
    fixtures = File.expand_path("../fixtures", __dir__)
    output, status = Open3.capture2e(Gem.ruby, "-I", fixtures, exe, *args)
    [output, status.exitstatus]
  end

  it "lists the commands each gem's commands.rb registers" do
    assert_equal ["Usage: skyward COMMAND [ARGS]\n  greet  Greet whoever's named\n", 0], skyward
  end

  it "runs a command with the arguments after its name" do
    assert_equal ["Hello, Ada and Grace!\n", 0], skyward("greet", "Ada", "Grace")
  end

  it "exits with the status run returns" do
    assert_equal 1, skyward("nope").last
  end
end
