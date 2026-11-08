# frozen_string_literal: true

class HealthAPI < Skyward::API
  description "Whether the app is up, for load balancers and uptime checks."

  get "/up", to: :show, summary: "Report that the app is up."

  # @rbs return: { status: "ok" }
  def show = { status: "ok" }
end
