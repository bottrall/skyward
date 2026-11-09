# frozen_string_literal: true

require "fileutils"

module Skyward::ORM::Migrations::Directory
  extend self

  PATH = "db/migrate" #: String

  # @rbs directory: String
  # @rbs name: String
  # @rbs return: String?
  def named(directory, name)
    files(directory).find { |file| File.basename(file).match?(/\A\d+_#{Regexp.escape(name)}\.sql\z/) }
  end

  # A migration's version is the timestamp its file name starts with.
  # @rbs directory: String
  # @rbs ran: Array[String]
  # @rbs return: Array[String]
  def pending(directory, ran) = files(directory).reject { |file| ran.include?(version(file)) }

  # @rbs directory: String
  # @rbs time: Time
  # @rbs name: String
  # @rbs sql: String
  # @rbs return: String
  def write(directory, time, name, sql)
    file = File.join(PATH, "#{time.getutc.strftime("%Y%m%d%H%M%S")}_#{name}.sql")
    FileUtils.mkdir_p(File.join(directory, PATH))
    File.write(File.join(directory, file), sql)
    file
  end

  private

  # @rbs directory: String
  # @rbs return: Array[String]
  def files(directory) = Dir.glob("#{PATH}/*.sql", base: directory).sort

  # @rbs file: String
  # @rbs return: String
  def version(file) = File.basename(file).split("_", 2).fetch(0)
end
