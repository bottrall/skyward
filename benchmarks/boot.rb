# frozen_string_literal: true

# rbs_inline: enabled

require "benchmark/ips"
require "fileutils"
require "json"
require "skyward/api"
require "skyward/orm"
require "stringio"
require "zeitwerk"

loader = Zeitwerk::Loader.new
loader.push_dir("#{__dir__}/lib")
loader.inflector.inflect("todos_api" => "TodosAPI", "routes_api" => "RoutesAPI")
loader.setup
loader.eager_load
