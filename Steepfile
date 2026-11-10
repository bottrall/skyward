# frozen_string_literal: true

D = Steep::Diagnostic

# Each gem's directory, and the Skyward gems it depends on.
GEMS = {
  core: { dir: "skyward-core", depends_on: [] },
  api: { dir: "skyward-api", depends_on: %i[core] },
  orm: { dir: "skyward-orm", depends_on: %i[core] },
  skyward: { dir: "skyward", depends_on: %i[core api orm] }
}.freeze

# Every target is unreferenced!, so its signatures stay private to it, and
# api and orm can't reach into each other. A project signature shared with a
# target that also loads it as a library would be declared twice, and Steep
# skips a target whose signatures don't load without saying so.
GEMS.each do |name, gem|
  target name do
    unreferenced!

    signature "#{gem.fetch(:dir)}/sig"
    library(*gem.fetch(:depends_on).map { |part| GEMS.fetch(part).fetch(:dir) })

    check "#{gem.fetch(:dir)}/lib"

    collection_config "rbs_collection.yaml"

    configure_code_diagnostics(D::Ruby.all_error)
  end
end

%i[todos todos_postgres].each do |example|
  target example do
    unreferenced!

    signature "examples/#{example}/sig"

    check "examples/#{example}/*.rb", "examples/#{example}/lib", "examples/#{example}/modules"

    # A library resolves its superclasses among the libraries alone, so orm's,
    # which subclass core's, need core's as a library too.
    library "skyward-core", "skyward-api", "skyward-orm"
    collection_config "rbs_collection.yaml"

    configure_code_diagnostics(D::Ruby.all_error)
  end
end

# Pins the type each of Skyward ORM's writes returns, as an app's code sees it.
target :orm_writes do
  unreferenced!

  signature "skyward-orm/test/fixtures/writes/sig"

  check "skyward-orm/test/fixtures/writes"

  library "skyward-core", "skyward-orm"
  collection_config "rbs_collection.yaml"

  configure_code_diagnostics(D::Ruby.all_error)
end
