# Contributing

Skyward is four gems in one repository. Each gem's `README.md` is its spec, and [`AGENTS.md`](AGENTS.md) holds the conventions for the code, for people and agents alike.

## Setup

You need the Ruby in `.ruby-version` for development. Skyward itself supports every Ruby that isn't end-of-life, and CI tests each one.

```sh
bin/setup
```

That installs the dev bundle, each gem's and example's own bundle, and the gem signatures Steep uses.

## Day to day

| Script         | Does                                                                      |
| -------------- | ------------------------------------------------------------------------- |
| `bin/test`     | runs every gem's and example's tests, each in its own bundle; pass files to run only those |
| `bin/lint`     | runs RuboCop; `bin/lint -a` autocorrects                                  |
| `bin/rbs`      | regenerates each gem's and example's `sig/generated` from its inline annotations       |
| `bin/rbs-watch` | regenerates them on every change                                          |
| `bin/typecheck` | checks the signatures are current, then runs Steep on every gem and example        |
| `bin/ci`       | everything CI runs, including building and installing the gems           |

Run `bin/ci` before you push.

## Pull requests

PR titles are [Conventional Commits](https://www.conventionalcommits.org/) with a scope naming the gem they change (`feat(api): add providers`, `fix(orm): quote column names`), because each becomes a squash commit on `main` and the changelog is built from them. Fill in the PR template.

## Releasing

The gems release together, at one version, through [release-please](https://github.com/googleapis/release-please). Every push to `main` updates its release PR, which bumps every gem's version, adds the changelog section and updates the lockfiles. Merging that PR tags the release, and `release.yml` then checks the versions, builds and installs the gems, and publishes them with RubyGems trusted publishing. There's nothing to run by hand.
