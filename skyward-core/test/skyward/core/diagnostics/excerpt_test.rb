# frozen_string_literal: true

require 'test_helper'

describe Skyward::Core::Diagnostics::Excerpt do
  excerpt = Skyward::Core::Diagnostics::Excerpt
  spot = lambda do |line, text, columns = nil, path: '/app/todos_api.rb'|
    Skyward::Core::Diagnostics::Spot.new(path:, line:, text:, columns:)
  end

  it 'is nil with no spots' do
    assert_nil excerpt.render([], directory: '/app')
  end

  it "puts carets under a spot's columns, below a header naming its file and line" do
    rendered = excerpt.render([spot.call(3, 'def show(todo_id:)', 9...17)], directory: '/app')

    expected = ['    todos_api.rb:3',
                '    def show(todo_id:)',
                '             ^^^^^^^^'].join("\n")

    assert_equal expected, rendered
  end

  it 'orders lines, removes their common indentation and collapses a gap to ...' do
    spots = [
      spot.call(9, '    def show(todo_id:)', 13...21),
      spot.call(4, '  get "/:id", to: :show'),
      spot.call(5, '  get "/", to: :index')
    ]

    expected = ['    todos_api.rb:9',
                '    get "/:id", to: :show',
                '    get "/", to: :index',
                '    ...',
                '      def show(todo_id:)',
                '               ^^^^^^^^'].join("\n")

    assert_equal expected, excerpt.render(spots, directory: '/app')
  end

  it 'names the first line in its header when no spot has columns' do
    assert_equal "    todos_api.rb:4\n    get \"/:id\"",
                 excerpt.render([spot.call(4, 'get "/:id"')], directory: '/app')
  end

  it 'puts a caret on an empty line, as at the end of a file' do
    assert_equal "    todos_api.rb:3\n\n    ^", excerpt.render([spot.call(3, '', 0...1)], directory: '/app')
  end

  it 'puts every spot on a line on one line of carets' do
    rendered = excerpt.render([spot.call(1, 'a b c', 0...1), spot.call(1, 'a b c', 4...5)], directory: '/app')

    assert_equal "    todos_api.rb:1\n    a b c\n    ^   ^", rendered
  end

  it 'makes a block for each file, in the order their spots come' do
    spots = [spot.call(2, 'type id = String', 5...7, path: '/app/sig/b.rbs'),
             spot.call(1, 'type id = Integer', 5...7, path: '/app/sig/a.rbs')]

    expected = ['    sig/b.rbs:2',
                '    type id = String',
                '         ^^',
                '',
                '    sig/a.rbs:1',
                '    type id = Integer',
                '         ^^'].join("\n")

    assert_equal expected, excerpt.render(spots, directory: '/app')
  end

  it 'keeps a path outside the directory as it is' do
    rendered = excerpt.render([spot.call(1, 'x', path: '/elsewhere/todos_api.rb')], directory: '/app')

    assert_equal "    /elsewhere/todos_api.rb:1\n    x", rendered
  end

  it 'makes a path relative to the current directory by default' do
    rendered = excerpt.render([spot.call(1, 'x', path: File.join(Dir.pwd, 'sig', 'a.rbs'))])

    assert_equal "    sig/a.rbs:1\n    x", rendered
  end
end
