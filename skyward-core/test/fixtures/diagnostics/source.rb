# frozen_string_literal: true

# Spots are found in this file's source; only its methods are looked up.
class DiagnosticsFixtures
  attr_reader :list #: Lisst
  attr_reader :count

  def show(todo_id:, limit: 10) = [todo_id, limit]

  def index = nil

  def create(
    title:,
    priority: :normal
  )
    [title, priority]
  end

  def routes
    get '/:id', to: :show
    default lsit_id: 0
    index :lsit_id
    get '/café/:id', to: :show
    clear
  end
end
