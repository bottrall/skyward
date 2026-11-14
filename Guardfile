# frozen_string_literal: true

guard :shell do
  watch(%r{^((skyward-core|skyward-api|skyward-orm|skyward)/lib/.*|examples/[^/]+/((lib|modules)/.*|[^/]+))\.rb$}) do
    system("bin/generate")
  end
end
