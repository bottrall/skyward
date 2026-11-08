# frozen_string_literal: true

require "minitest/autorun"
require "stringio"

# App logs every request to the $stdout it boots with, which would bury the
# test report, so it boots with one of its own.
stdout = $stdout
$stdout = StringIO.new
require_relative "../app"
$stdout = stdout
