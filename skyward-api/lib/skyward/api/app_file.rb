# frozen_string_literal: true

module Skyward::API::AppFile
  extend self

  FILE = "app.rb" #: String

  ASSIGNMENT = "App = Skyward.app { ... }" #: String

  # @rbs (String directory, out: _Writer, kernel: singleton(Kernel)) { (Skyward::API::Application) -> String } -> void
  def run(directory, out:, kernel:, &)
    app = load(directory)
    case app
    when String then kernel.abort(app)
    else out.write(yield app)
    end
  # Booting the app raises it, and so can what's made from the app, such as
  # an OpenAPI document with two operations of one ID.
  rescue Skyward::BootError => e
    kernel.abort(e.message)
  end

  # @rbs directory: String
  # @rbs return: Skyward::API::Application | String
  def load(directory)
    path = File.join(directory, FILE)
    unless File.file?(path)
      return "skyward: no #{FILE} in #{directory}. Run skyward where your app's #{FILE} assigns #{ASSIGNMENT}."
    end

    require path
    app = Object.const_get(:App) if Object.const_defined?(:App)
    return app if app.is_a?(Skyward::API::Application)

    "skyward: #{path} doesn't assign a Skyward app to App. Assign #{ASSIGNMENT}."
  end
end
