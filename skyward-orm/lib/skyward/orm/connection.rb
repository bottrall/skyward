# frozen_string_literal: true

module Skyward::ORM::Connection
  # One for the process: Skyward.connect sets its database, for every query. It
  # lives here, not in session.rb, because Zeitwerk expects that file to define only Session.
  SESSION = Skyward::ORM::Connection::Session.new #: Skyward::ORM::Connection::Session
end
