# frozen_string_literal: true

# rbs_inline: enabled

# The app has no docs, so routes can share their methods.
class Bench::RoutesAPI < Skyward::API
  get    "/items",                        to: :list
  post   "/items",                        to: :list
  get    "/items/:id",                    to: :show
  put    "/items/:id",                    to: :show
  patch  "/items/:id",                    to: :show
  delete "/items/:id",                    to: :show
  get    "/items/:id/parts",              to: :show
  post   "/items/:id/parts",              to: :show
  get    "/items/:id/parts/:part_id",     to: :part
  delete "/items/:id/parts/:part_id",     to: :part
  get    "/orders",                       to: :list
  post   "/orders",                       to: :list
  get    "/orders/:id",                   to: :show
  put    "/orders/:id",                   to: :show
  patch  "/orders/:id",                   to: :show
  delete "/orders/:id",                   to: :show
  get    "/orders/:id/lines",             to: :show
  post   "/orders/:id/lines",             to: :show
  delete "/orders/:id/lines/:line_id",    to: :line
  get    "/orders/:id/lines/:line_id",    to: :line

  # @rbs return: Array[{ id: Integer }]
  def list = []

  # @rbs id: Integer
  # @rbs return: { id: Integer }
  def show(id:) = { id: }

  # @rbs id: Integer
  # @rbs part_id: Integer
  # @rbs return: { id: Integer, part_id: Integer }
  def part(id:, part_id:) = { id:, part_id: }

  # @rbs id: Integer
  # @rbs line_id: Integer
  # @rbs return: { id: Integer, line_id: Integer }
  def line(id:, line_id:) = { id:, line_id: }
end
