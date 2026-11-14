# frozen_string_literal: true

module RuboCop::Cop::Local
  # rbs-inline types a constant assigned another constant (`Todos =
  # Todos::Service`) as untyped, and Steep then checks nothing reached
  # through it.
  class TypedConstantAlias < RuboCop::Cop::Base
    MSG = 'Give this alias its type (`#: singleton(Some::Module)` for a module), or rbs-inline makes it untyped.'

    def on_casgn(node)
      return unless node.expression&.const_type?

      line = node.last_line
      typed = processed_source.comments.any? { |comment| comment.loc.line == line && comment.text.start_with?('#:') }
      add_offense(node) unless typed
    end
  end
end
