# frozen_string_literal: true

require "skyward/orm"
require "zeitwerk"

# Autoloaded and never eager-loaded, so nothing has loaded a table class when
# skyward migration looks for them.
loader = Zeitwerk::Loader.new
loader.push_dir(File.join(__dir__, "app"))
loader.setup

# The test that runs it says which database.
Skyward.connect(ENV.fetch("DATABASE_URL"))
