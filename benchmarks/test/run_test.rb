# frozen_string_literal: true

require 'open3'
require 'test_helper'

# Only refusals, since a run that's accepted times every scenario it names.
describe 'run.rb' do
  it "exits 1 naming each name no scenario's starts with, and writes nothing" do
    _out, err, status = Open3.capture3(Gem.ruby, 'run.rb', 'api', 'api.foo', chdir: File.expand_path('..', __dir__))

    assert_equal [1, "No benchmark's name starts with api.foo\n"], [status.exitstatus, err]
  end
end
