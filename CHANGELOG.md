# Changelog

## [0.2.0](https://github.com/bottrall/skyward/compare/v0.1.0...v0.2.0) (2026-11-08)


### ⚠ BREAKING CHANGES

* **api,core:** every public constant moves into its gem's namespace, as listed above.

### Features

* **api:** add an error-reporting hook, and backtraces in development ([#84](https://github.com/bottrall/skyward/issues/84)) ([ffeb9d9](https://github.com/bottrall/skyward/commit/ffeb9d95ad77daded640ea34861c91034be3554e)), closes [#38](https://github.com/bottrall/skyward/issues/38)
* **api:** add bad_request, unauthorized, forbidden and redirect ([#89](https://github.com/bottrall/skyward/issues/89)) ([2ca4e38](https://github.com/bottrall/skyward/commit/2ca4e38e3d89ee3cc4db5cf3905a710e250215bc)), closes [#31](https://github.com/bottrall/skyward/issues/31)
* **api:** add middleware with use ([#77](https://github.com/bottrall/skyward/issues/77)) ([fb40c7e](https://github.com/bottrall/skyward/commit/fb40c7e5c89d0748767bd6f5c39d83360e1b5a33))
* **api:** add providers ([#105](https://github.com/bottrall/skyward/issues/105)) ([eede9ef](https://github.com/bottrall/skyward/commit/eede9efc779f4342171e926b6419b8d99c66ad65))
* **api:** add request IDs ([#76](https://github.com/bottrall/skyward/issues/76)) ([3577574](https://github.com/bottrall/skyward/commit/3577574c7c854d1165a68d3719a67c97afb09c18)), closes [#36](https://github.com/bottrall/skyward/issues/36)
* **api:** add skyward check ([#106](https://github.com/bottrall/skyward/issues/106)) ([30f9ea1](https://github.com/bottrall/skyward/commit/30f9ea1f15dbe8a056b32e3fb9b6e03bdc1433b4))
* **api:** add skyward routes and skyward openapi ([#103](https://github.com/bottrall/skyward/issues/103)) ([0f903b1](https://github.com/bottrall/skyward/commit/0f903b15151f109f724b52d2b7d77a67c7e36f8a))
* **api:** add skyward serve ([#80](https://github.com/bottrall/skyward/issues/80)) ([634c627](https://github.com/bottrall/skyward/commit/634c6279a1f803ee03bde70710f11a9c1749be8e)), closes [#39](https://github.com/bottrall/skyward/issues/39)
* **api:** add Skyward::Test.client ([#78](https://github.com/bottrall/skyward/issues/78)) ([94c61c1](https://github.com/bottrall/skyward/commit/94c61c1a29a59fdfb500482cc5e91dda79d7beef)), closes [#26](https://github.com/bottrall/skyward/issues/26)
* **api:** add the request: keyword ([#97](https://github.com/bottrall/skyward/issues/97)) ([88d65bf](https://github.com/bottrall/skyward/commit/88d65bf3a252c457c79ba1b570845b37164ff9bd)), closes [#29](https://github.com/bottrall/skyward/issues/29)
* **api:** add untyped endpoints and strict: ([#101](https://github.com/bottrall/skyward/issues/101)) ([f3d87c7](https://github.com/bottrall/skyward/commit/f3d87c726783cf5f17e28ecc94984e18e9c673d2))
* **api:** answer 405, HEAD and OPTIONS ([#79](https://github.com/bottrall/skyward/issues/79)) ([ccc2588](https://github.com/bottrall/skyward/commit/ccc25883264770bdf36c4407d6349a1164df9acd)), closes [#24](https://github.com/bottrall/skyward/issues/24)
* **api:** build and route an app with Skyward.app ([#75](https://github.com/bottrall/skyward/issues/75)) ([4547dd5](https://github.com/bottrall/skyward/commit/4547dd5036281059dc148321e752693041cf2680)), closes [#20](https://github.com/bottrall/skyward/issues/20)
* **api:** build the OpenAPI 3.1 document ([#99](https://github.com/bottrall/skyward/issues/99)) ([d6cb52c](https://github.com/bottrall/skyward/commit/d6cb52c91656655331fcbe2f7a889709a6c92d2c))
* **api:** check routes and signatures at boot ([#85](https://github.com/bottrall/skyward/issues/85)) ([5408433](https://github.com/bottrall/skyward/commit/540843332ff18dd448d13a0da2c7db7d27f8a6d9)), closes [#21](https://github.com/bottrall/skyward/issues/21)
* **api:** coerce and validate inputs ([#95](https://github.com/bottrall/skyward/issues/95)) ([a599336](https://github.com/bottrall/skyward/commit/a599336bb303107138cbb3ce2eb574232301870c))
* **api:** declare routes on an API class ([#73](https://github.com/bottrall/skyward/issues/73)) ([a6ead24](https://github.com/bottrall/skyward/commit/a6ead249f37e79a4157ce901f4cc9e70080f11fd)), closes [#19](https://github.com/bottrall/skyward/issues/19)
* **api:** log requests as structured JSON, with logger: ([#83](https://github.com/bottrall/skyward/issues/83)) ([7be9dd6](https://github.com/bottrall/skyward/commit/7be9dd693f7a3dd1b47a6aa1cce05388e4150b1b))
* **api:** reload skyward serve on file changes ([#87](https://github.com/bottrall/skyward/issues/87)) ([83f1a21](https://github.com/bottrall/skyward/commit/83f1a21402a79f1df7bc2aa969aab4518ca3ec91)), closes [#41](https://github.com/bottrall/skyward/issues/41)
* **api:** return a Rack triple ([#90](https://github.com/bottrall/skyward/issues/90)) ([50066c5](https://github.com/bottrall/skyward/commit/50066c51ebc12e8e140b169c48154472d4221f61)), closes [#32](https://github.com/bottrall/skyward/issues/32)
* **api:** serialize responses by their declared type ([#88](https://github.com/bottrall/skyward/issues/88)) ([b4e5c3c](https://github.com/bottrall/skyward/commit/b4e5c3c0e08118610dd83d26736e85f3f83436f1))
* **api:** serve /docs with a configurable Scalar source ([#100](https://github.com/bottrall/skyward/issues/100)) ([046584f](https://github.com/bottrall/skyward/commit/046584f60e76d8a91dd826a1fa8baf03403299c9))
* **api:** serve static files with ETags ([#81](https://github.com/bottrall/skyward/issues/81)) ([0109929](https://github.com/bottrall/skyward/commit/01099291bbabe17e3f5b517add947c2b479ff7b2))
* **api:** support Hash[String, T] ([#102](https://github.com/bottrall/skyward/issues/102)) ([d20cf98](https://github.com/bottrall/skyward/commit/d20cf98ce51e966a0b7b14a2bfef24d2de75e664)), closes [#35](https://github.com/bottrall/skyward/issues/35)
* **core:** add the skyward executable and command registry ([#71](https://github.com/bottrall/skyward/issues/71)) ([85644af](https://github.com/bottrall/skyward/commit/85644afc87c23ba012be5849f2d1fe41db2dc04c)), closes [#16](https://github.com/bottrall/skyward/issues/16)
* **core:** load RBS signatures ([#74](https://github.com/bottrall/skyward/issues/74)) ([d662b35](https://github.com/bottrall/skyward/commit/d662b35d025a49cca5fcc292b53beb76ff71d314)), closes [#17](https://github.com/bottrall/skyward/issues/17)
* **core:** read RBS types into values ([#82](https://github.com/bottrall/skyward/issues/82)) ([14f51c4](https://github.com/bottrall/skyward/commit/14f51c405ebc96494915f7d00901d386e07755aa))
* **examples:** add an in-memory todos API as the end-to-end test ([#104](https://github.com/bottrall/skyward/issues/104)) ([f6b52a0](https://github.com/bottrall/skyward/commit/f6b52a03026cffcbc5f1c90fd6178510c2ef1722))


### Bug Fixes

* **api:** bound the size of union mismatch messages in a 422 ([#96](https://github.com/bottrall/skyward/issues/96)) ([cce7f5d](https://github.com/bottrall/skyward/commit/cce7f5d33aceb0df4f81db4134dcf69e53471032)), closes [#91](https://github.com/bottrall/skyward/issues/91)
* **api:** stop nested unions multiplying coercion cost ([#98](https://github.com/bottrall/skyward/issues/98)) ([8cd74a2](https://github.com/bottrall/skyward/commit/8cd74a2acf4c2ec6334444a5d42da5124c58dca9)), closes [#92](https://github.com/bottrall/skyward/issues/92)
* **core:** silence rbs collection warnings in bin/setup ([#108](https://github.com/bottrall/skyward/issues/108)) ([b400cc2](https://github.com/bottrall/skyward/commit/b400cc2e16a46a610846ad2c152f79a257abf43e))


### Code Refactoring

* **api,core:** group skyward-api by feature and keep only gem namespaces under Skyward ([#109](https://github.com/bottrall/skyward/issues/109)) ([b4304ba](https://github.com/bottrall/skyward/commit/b4304ba84f90628a4ede263f5d0b8638d88f607b))

## 0.1.0

### All gems

- The skeleton: every gem builds, installs and loads, and each README describes what's coming. Nothing is usable yet.
