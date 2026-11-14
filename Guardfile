# frozen_string_literal: true

sources = %r{
  ^((skyward-core|skyward-api|skyward-orm|skyward)/lib/.*
  |(examples/[^/]+|benchmarks)/((lib|modules)/.*|[^/]+))\.rb$
}x

guard :shell do
  watch(sources) do
    system('bin/generate')
  end
end
