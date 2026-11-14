# frozen_string_literal: true

require 'test_helper'

# Only checks, since timing takes seconds a scenario. Each runs in a process
# of its own, as Bench::Runner runs it.
describe 'group.rb' do
  def check(group, names = '')
    system(Gem.ruby, 'group.rb', group, names, chdir: File.expand_path('..', __dir__))
  end

  it "checks the api group's scenarios" do
    assert check('api')
  end

  it "checks the orm.sqlite group's scenarios on SQLite" do
    assert check('orm.sqlite')
  end

  it "checks the orm.postgresql group's scenarios on PostgreSQL" do
    skip 'Set TEST_POSTGRES_URL to run the PostgreSQL scenarios' unless POSTGRES

    assert check('orm.postgresql')
  end
end
