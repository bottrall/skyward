# frozen_string_literal: true

require "test_helper"
require "tmpdir"

describe Skyward::ORM::Migrations::Directory do
  directory = Skyward::ORM::Migrations::Directory

  def app(*files)
    Dir.mktmpdir do |app|
      files.each do |file|
        FileUtils.mkdir_p(File.join(app, File.dirname(file)))
        File.write(File.join(app, file), "")
      end
      yield app
    end
  end

  describe ".named" do
    it "finds the migration with that name" do
      app("db/migrate/20261018093000_create_todos.sql", "db/migrate/20261019141500_add_notes_to_todos.sql") do |path|
        assert_equal "db/migrate/20261018093000_create_todos.sql", directory.named(path, "create_todos")
      end
    end

    it "finds none when only a longer name ends with it" do
      app("db/migrate/20261019141500_add_notes_to_todos.sql") do |path|
        assert_nil directory.named(path, "to_todos")
      end
    end

    it "finds none in an app with no migrations" do
      app { |path| assert_nil directory.named(path, "create_todos") }
    end
  end

  describe ".pending" do
    it "lists the migrations whose versions haven't run, in order" do
      files = %w[20261018093000_create_todos 20261019141500_add_notes 20261020080000_add_tags].map do |name|
        "db/migrate/#{name}.sql"
      end

      app(*files.reverse) do |path|
        assert_equal files.drop(1), directory.pending(path, ["20261018093000"])
      end
    end
  end

  describe ".write" do
    it "writes the SQL to a file named by the UTC time and the name, and returns its path" do
      app do |path|
        file = directory.write(path, Time.new(2026, 10, 18, 19, 30, 0, "+10:00"), "create_todos", "SELECT 1;\n")

        assert_equal ["db/migrate/20261018093000_create_todos.sql", "SELECT 1;\n"],
                     [file, File.read(File.join(path, file))]
      end
    end
  end
end
