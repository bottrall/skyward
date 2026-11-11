# frozen_string_literal: true

require "test_helper"
require "sqlite3"

describe Skyward::ORM::Connection::Session do
  sqlite = Skyward::ORM::Adapters::SQLite
  reader = Skyward::Core::Types::Reader.new(Skyward::Core::Signatures.load(File.expand_path("missing", __dir__)))

  # Records each call, for a database whose hold or release raises.
  recording = Data.define(:calls, :raises) do
    def hold = record(:hold)

    def release = record(:release)

    def record(call)
      calls << call
      raise IOError, "raised at #{call}" if raises == call
    end
  end

  let(:session) { Skyward::ORM::Connection::Session.new }
  let(:database) { connected }
  let(:other) { connected }

  # One connection, so a database held twice would wait for a second one, and
  # its in-memory database keeps what's written while that connection is open.
  define_method(:connected) do
    Skyward::ORM::Database.new(
      sqlite,
      Skyward::ORM::Connection::Pool.new(1, -> { sqlite.connect(":memory:") }, timeout: 0.1),
      Skyward::ORM::Tables::ColumnTypes.new(reader),
      [],
      check: true
    ).tap { |connected| connected.execute("CREATE TABLE lists (name TEXT)") }
  end

  def insert(database, name) = database.execute("INSERT INTO lists (name) VALUES (?)", [name])

  def names(database) = database.execute("SELECT name FROM lists").flatten

  describe "#connect" do
    it "returns the database" do
      assert_same database, session.connect(database)
    end
  end

  describe "#database" do
    it "is the database connected" do
      session.connect(database)

      assert_same database, session.database
    end

    it "says to connect when nothing has" do
      error = assert_raises(Skyward::Core::BootError) { session.database }

      assert_equal "Skyward ORM isn't connected. Call Skyward.connect(url) where your app boots.", error.message
    end
  end

  describe "#using" do
    before { session.connect(database) }

    it "makes the database current for the block, and returns the block's value" do
      assert_equal [other, :done], session.using(other) { [session.database, :done] }
    end

    it "makes it current with nothing connected" do
      unconnected = Skyward::ORM::Connection::Session.new

      assert_same other, unconnected.using(other) { unconnected.database }
    end

    it "makes the previous one current again after the block" do
      session.using(other) { nil }

      assert_same database, session.database
    end

    it "makes the previous one current again when the block raises" do
      assert_raises(IOError) { session.using(other) { raise IOError } }

      assert_same database, session.database
    end

    it "makes the previous one current again when the block throws" do
      catch(:out) { session.using(other) { throw :out } }

      assert_same database, session.database
    end

    it "makes the previous one current again when the block breaks" do
      session.using(other) { break }

      assert_same database, session.database
    end

    it "nests, making the outer one current again after the inner block" do
      inner = connected
      seen = session.using(other) { [session.using(inner) { session.database }, session.database] }

      assert_equal [inner, other], seen
    end

    it "leaves a fiber already running on its own database" do
      running = Fiber.new { loop { Fiber.yield session.database } }

      assert_same database, session.using(other) { running.resume }
    end

    it "leaves a thread already running on its own database" do
      asked = Thread::Queue.new
      running = Thread.new do
        asked.pop
        session.database
      end
      session.using(other) do
        asked << true
        running.join
      end

      assert_same database, running.value
    end

    it "switches the fibers and threads the block starts" do
      seen = session.using(other) { [Fiber.new { session.database }.resume, Thread.new { session.database }.value] }

      assert_equal [other, other], seen
    end
  end

  describe "#hold" do
    before { session.connect(database) }

    it "holds a transaction on the current database until #release" do
      session.hold
      insert(database, "Home")
      session.release

      assert_empty names(database)
    end

    it "holds one on each database its fiber switches to, once, until #release" do
      session.hold
      session.using(other) { insert(other, "Home") }
      session.using(other) { insert(other, "Work") }
      session.release

      assert_equal [[], []], [names(database), names(other)]
    end

    it "doesn't hold the current database again when its fiber switches to it" do
      session.hold
      session.using(database) { insert(database, "Home") }
      session.release

      assert_empty names(database)
    end

    it "doesn't hold a database a thread it starts switches to" do
      session.hold
      Thread.new { session.using(other) { insert(other, "Home") } }.join
      session.release

      assert_equal ["Home"], names(other)
    end

    it "doesn't hold a database switched to when nothing holds" do
      session.using(other) { insert(other, "Home") }

      assert_equal ["Home"], names(other)
    end

    it "keeps a database whose hold raises, for #release" do
      failing = recording.new(calls: [], raises: :hold)
      session.connect(failing)

      assert_raises(IOError) { session.hold }
      session.release

      assert_equal %i[hold release], failing.calls
    end
  end

  describe "#release" do
    it "does nothing when nothing is held" do
      assert_nil session.release
    end

    it "releases every database it holds, even when one's release raises" do
      failing = recording.new(calls: [], raises: :release)
      session.connect(database)
      session.hold
      session.using(failing) { nil }
      session.using(other) { insert(other, "Home") }

      assert_raises(IOError) { session.release }
      assert_equal [[], %i[hold release]], [names(other), failing.calls]
    end

    it "leaves nothing held afterwards" do
      session.connect(database)
      session.hold
      session.release
      session.using(other) { insert(other, "Home") }

      assert_equal ["Home"], names(other)
    end
  end

  describe "#check?" do
    it "is on" do
      assert_predicate session, :check?
    end
  end

  describe "#without_check" do
    it "turns the check off for the block" do
      refute(session.without_check { session.check? })
    end

    it "returns the block's value" do
      assert_equal(:booted, session.without_check { :booted })
    end

    it "turns it back on afterwards" do
      session.without_check { nil }

      assert_predicate session, :check?
    end

    it "turns it back on when the block raises" do
      assert_raises(Skyward::Core::BootError) { session.without_check { raise Skyward::Core::BootError } }

      assert_predicate session, :check?
    end
  end
end
