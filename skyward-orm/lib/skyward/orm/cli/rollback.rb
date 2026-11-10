# frozen_string_literal: true

module Skyward::ORM::CLI::Rollback
  extend self

  # @rbs (directory: String, out: _Writer, kernel: singleton(Kernel), session: Skyward::ORM::Connection::Session,
  #   generate: ^() -> String?) -> void
  def run(directory:, out:, kernel:, session:, generate:)
    Skyward::ORM::CLI::BootFile.boot(directory, session, kernel, generate) do |database|
      runner = Skyward::ORM::Migrations::Runner
      rolled_back = database.rollback(runner.read(File.join(directory, Skyward::ORM::Migrations::Directory::PATH)))
      case rolled_back
      when String then out.write("Rolled back #{rolled_back}\n")
      else kernel.abort(runner.rollback_message(rolled_back))
      end
    end
  end
end
