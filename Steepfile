# frozen_string_literal: true

D = Steep::Diagnostic

# Each gem's directory, and the Skyward gems it depends on.
GEMS = {
  core: { dir: "skyward-core", depends_on: [] },
  api: { dir: "skyward-api", depends_on: %i[core] },
  orm: { dir: "skyward-orm", depends_on: %i[core] },
  skyward: { dir: "skyward", depends_on: %i[core api orm] }
}.freeze

# Steep gives a signature file to the first target that lists it, and other
# targets see it only when that owner isn't `unreferenced!`. Every gem depends
# on core, so core's signatures are shared. Every other target is
# unreferenced!, so its signatures stay private to it, and api and orm can't
# reach into each other.
GEMS.each do |name, gem|
  target name do
    unreferenced! unless name == :core

    [name, *gem.fetch(:depends_on)].each { |part| signature "#{GEMS.fetch(part).fetch(:dir)}/sig" }

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

    # api's and orm's signatures belong to their own targets, which no other
    # target sees, so the example loads them as the gems' libraries instead.
    # orm's subclass core's, and a library resolves its superclasses among the
    # libraries alone, so core comes as one too.
    library "skyward-core", "skyward-api", "skyward-orm"
    collection_config "rbs_collection.yaml"

    configure_code_diagnostics(D::Ruby.all_error)
  end
end
