# Changelog

## [0.3.0](https://github.com/bottrall/skyward/compare/v0.2.0...v0.3.0) (2026-11-11)


### Features

* **api:** regenerate sig/generated on save under skyward serve ([#163](https://github.com/bottrall/skyward/issues/163)) ([f8f79b4](https://github.com/bottrall/skyward/commit/f8f79b4d6686b139d6b6086c760ed62b8a7fb17c)), closes [#162](https://github.com/bottrall/skyward/issues/162)
* **core:** keep sig/generated current for every command that reads types ([#150](https://github.com/bottrall/skyward/issues/150)) ([2105424](https://github.com/bottrall/skyward/commit/21054242fdf8e8e90ea67204507320b6758a07a0)), closes [#145](https://github.com/bottrall/skyward/issues/145)
* **examples:** move the todos example onto the ORM ([#133](https://github.com/bottrall/skyward/issues/133)) ([d616e61](https://github.com/bottrall/skyward/commit/d616e615190061c82e1d3cd90b01db2633e71bb6)), closes [#66](https://github.com/bottrall/skyward/issues/66)
* **examples:** split the todos example into SQLite and PostgreSQL apps ([#138](https://github.com/bottrall/skyward/issues/138)) ([3ce3be1](https://github.com/bottrall/skyward/commit/3ce3be1bb01de3a19741c948a23c487716641184)), closes [#137](https://github.com/bottrall/skyward/issues/137)
* **orm:** add a delete that returns a violation ([#130](https://github.com/bottrall/skyward/issues/130)) ([2bf5d8a](https://github.com/bottrall/skyward/commit/2bf5d8a2a8a7c581a14b1592ac54719b11be1a4f)), closes [#58](https://github.com/bottrall/skyward/issues/58)
* **orm:** add empty migrations ([#116](https://github.com/bottrall/skyward/issues/116)) ([243b3fc](https://github.com/bottrall/skyward/commit/243b3fcb51294fbbbf1de100d20d5802dbda8167)), closes [#62](https://github.com/bottrall/skyward/issues/62)
* **orm:** add insert, insert!, update, update! and delete! with RETURNING ([#129](https://github.com/bottrall/skyward/issues/129)) ([9e40ca1](https://github.com/bottrall/skyward/commit/9e40ca1c197a7af3b9d6d72e0e3cc78da9151231)), closes [#57](https://github.com/bottrall/skyward/issues/57)
* **orm:** add into projections ([#125](https://github.com/bottrall/skyward/issues/125)) ([4c8e335](https://github.com/bottrall/skyward/commit/4c8e3354672cf42288bbeb317ca6da8fe52dfd21)), closes [#51](https://github.com/bottrall/skyward/issues/51)
* **orm:** add join and left_join ([#126](https://github.com/bottrall/skyward/issues/126)) ([824fe78](https://github.com/bottrall/skyward/commit/824fe7871e313e0a5cc75dbe47eabd61e8eb00ac))
* **orm:** add limit, offset and exists? ([#120](https://github.com/bottrall/skyward/issues/120)) ([026b885](https://github.com/bottrall/skyward/commit/026b885ebc7b07f8c0be2c8d970e6ac0c0fb6f5f))
* **orm:** add ranges, SQL strings, exclude and or ([#124](https://github.com/bottrall/skyward/issues/124)) ([797efd6](https://github.com/bottrall/skyward/commit/797efd6cd022c42ac2322d541e30f7e067497d42))
* **orm:** add skyward rollback and skyward status ([#127](https://github.com/bottrall/skyward/issues/127)) ([a0eb1dd](https://github.com/bottrall/skyward/commit/a0eb1dd41bb13900ebb0a8f495083c363d6bfb1a)), closes [#64](https://github.com/bottrall/skyward/issues/64)
* **orm:** add Skyward::ORM::Transactional ([#119](https://github.com/bottrall/skyward/issues/119)) ([9182f6f](https://github.com/bottrall/skyward/commit/9182f6fca0feaa1e9d788e2e40d6b92fbf384a4a)), closes [#59](https://github.com/bottrall/skyward/issues/59)
* **orm:** add Skyward.query for raw SQL ([#118](https://github.com/bottrall/skyward/issues/118)) ([c6d534b](https://github.com/bottrall/skyward/commit/c6d534b7b89501922387fca5231de184c328f142)), closes [#55](https://github.com/bottrall/skyward/issues/55)
* **orm:** add the adapter seam, with a SQLite adapter ([#112](https://github.com/bottrall/skyward/issues/112)) ([9e7f59f](https://github.com/bottrall/skyward/commit/9e7f59fb376a66e2c55ec53279381b658f2bf237)), closes [#46](https://github.com/bottrall/skyward/issues/46)
* **orm:** add the PostgreSQL adapter ([#128](https://github.com/bottrall/skyward/issues/128)) ([eb77ef1](https://github.com/bottrall/skyward/commit/eb77ef114a4d704e25f22d3e511c77233dbd9ea1))
* **orm:** check the schema at connect ([#114](https://github.com/bottrall/skyward/issues/114)) ([f2e8068](https://github.com/bottrall/skyward/commit/f2e80681df3a9f4f5833f1138cceff2713ecaff9))
* **orm:** check values against column types when a query is built ([#121](https://github.com/bottrall/skyward/issues/121)) ([53d5341](https://github.com/bottrall/skyward/commit/53d53414964cb8c0c7e9d4b0ba4c71db55f69d8e)), closes [#56](https://github.com/bottrall/skyward/issues/56)
* **orm:** declare tables, with rows as frozen values ([#110](https://github.com/bottrall/skyward/issues/110)) ([0368eee](https://github.com/bottrall/skyward/commit/0368eeedbeb6d6682dd645e3044bfb72ecd9c313)), closes [#45](https://github.com/bottrall/skyward/issues/45)
* **orm:** generate migrations for drops, changes, indexes and constraints ([#122](https://github.com/bottrall/skyward/issues/122)) ([7623dc8](https://github.com/bottrall/skyward/commit/7623dc8212305f85beb3a529218571f85174ae4f))
* **orm:** generate migrations for new tables and columns ([#113](https://github.com/bottrall/skyward/issues/113)) ([31f1f89](https://github.com/bottrall/skyward/commit/31f1f8922ee4934f2a18890571c6d8a90404fedc))
* **orm:** pool connections, with transactions held per fiber ([#115](https://github.com/bottrall/skyward/issues/115)) ([268cb70](https://github.com/bottrall/skyward/commit/268cb70161f54204c97a90cf9a06e47825a9ad16))
* **orm:** query with where, order, group, first, count and find_by ([#117](https://github.com/bottrall/skyward/issues/117)) ([3d322d2](https://github.com/bottrall/skyward/commit/3d322d2ddcdf466d4227d83bc88337240f4978b0))
* **orm:** return nothing from writes unless into asks for rows ([#151](https://github.com/bottrall/skyward/issues/151)) ([adb8a30](https://github.com/bottrall/skyward/commit/adb8a30c84987b5aadaa9f2ce64f09ac017b8ec8)), closes [#144](https://github.com/bottrall/skyward/issues/144)
* **orm:** run migrations with a lock and checksums ([#123](https://github.com/bottrall/skyward/issues/123)) ([85125aa](https://github.com/bottrall/skyward/commit/85125aa6d80ea426ae2771813634967b8713ceaf))
* **skyward:** add skyward new ([#134](https://github.com/bottrall/skyward/issues/134)) ([f07637f](https://github.com/bottrall/skyward/commit/f07637f5ebc4e09aec2be002972639bbb37b798a)), closes [#67](https://github.com/bottrall/skyward/issues/67)
* **skyward:** make skyward new write a blank app ([#152](https://github.com/bottrall/skyward/issues/152)) ([c041473](https://github.com/bottrall/skyward/commit/c041473269548d3fe0c41c3d66e159a10716dbf5)), closes [#147](https://github.com/bottrall/skyward/issues/147)


### Bug Fixes

* **api,orm:** refuse non-finite Floats where they can't round-trip ([#156](https://github.com/bottrall/skyward/issues/156)) ([0e7e865](https://github.com/bottrall/skyward/commit/0e7e86539ac62269aa0d2b22b59947abfd4def8b)), closes [#132](https://github.com/bottrall/skyward/issues/132)
* **orm:** accept uuid, citext and real columns when checking the schema ([#161](https://github.com/bottrall/skyward/issues/161)) ([310eb6e](https://github.com/bottrall/skyward/commit/310eb6e2491bde700d74c6d47eecd10d50a0be62)), closes [#159](https://github.com/bottrall/skyward/issues/159)
* **orm:** roll back a transaction interrupted right after BEGIN ([#160](https://github.com/bottrall/skyward/issues/160)) ([2c617d1](https://github.com/bottrall/skyward/commit/2c617d1979cf41b449dba3975e7e0bccc15c04f3)), closes [#141](https://github.com/bottrall/skyward/issues/141)
* **skyward:** put Falcon in the generated app's default gem group ([#149](https://github.com/bottrall/skyward/issues/149)) ([04ec1a6](https://github.com/bottrall/skyward/commit/04ec1a6949752fbd1fe9ba694c677094ce979624)), closes [#146](https://github.com/bottrall/skyward/issues/146)
* **skyward:** run skyward new's bundle install outside the outer bundle ([#155](https://github.com/bottrall/skyward/issues/155)) ([23cb8eb](https://github.com/bottrall/skyward/commit/23cb8ebc27f5a60b9e5583422aa011626d2d09ac)), closes [#135](https://github.com/bottrall/skyward/issues/135)

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
