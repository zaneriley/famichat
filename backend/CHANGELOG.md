# Changelog

Automatically updated using Release Please. Follows [semantic versioning](https://semver.org/spec/v2.0.0.html), using [conventional commits](https://www.conventionalcommits.org/en/v1.0.0/).


## [0.4.1-alpha.1](https://github.com/zaneriley/personal-site/compare/v0.4.0-alpha.1...v0.4.1-alpha.1) (2024-09-14)


### Features

* **release:** Create release setup to migrate DB and pull repo ([#45](https://github.com/zaneriley/personal-site/issues/45)) ([d4b26ae](https://github.com/zaneriley/personal-site/commit/d4b26ae591ba1b0f401e0f52e61551e749d4c262))

## [0.4.0-alpha.1](https://github.com/zaneriley/personal-site/compare/v0.3.3-alpha.1...v0.4.0-alpha.1) (2024-09-09)


### Features

* **webhook:** implement GitHub webhook for content updates ([2c23562](https://github.com/zaneriley/personal-site/commit/2c2356209d0cae5fa7089d84666975d711d7a073))

## [0.3.3-alpha.1](https://github.com/zaneriley/personal-site/compare/v0.3.2-alpha.1...v0.3.3-alpha.1) (2024-08-18)


### Documentation

* **readme:** update features and development tools information ([a385f3d](https://github.com/zaneriley/personal-site/commit/a385f3d8ea9fbe6dfa0d99711b624b1630741246))

## [0.3.2-alpha.1](https://github.com/zaneriley/personal-site/compare/v0.3.1-alpha.1...v0.3.2-alpha.1) (2024-08-17)


### Bug Fixes

* **docker:** ensure static assets directory exists in entrypoint script ([086c3c1](https://github.com/zaneriley/personal-site/commit/086c3c17dc06180b8dcb6bea42de808ab2bf6a94))

## [0.3.1-alpha.1](https://github.com/zaneriley/personal-site/compare/v0.3.0-alpha.1...v0.3.1-alpha.1) (2024-08-16)


### Bug Fixes

* remove duplicate Plug.Exception implementation for Ecto.NoResultsError ([31d5a91](https://github.com/zaneriley/personal-site/commit/31d5a9172c32010fc2ba8bbf23f3dfcec7fa6cd9))

## [0.3.0-alpha.1](https://github.com/zaneriley/personal-site/compare/v0.2.0-alpha.1...v0.3.0-alpha.1) (2024-08-16)


### Features

* **content:** implement markdown rendering with custom components and caching ([#37](https://github.com/zaneriley/personal-site/issues/37)) ([0ed94ff](https://github.com/zaneriley/personal-site/commit/0ed94ff3c94a5e02b91b7674148d1151f28d30d2))

## [0.2.0-alpha.1](https://github.com/zaneriley/personal-site/compare/v0.1.1-alpha.1...v0.2.0-alpha.1) (2024-07-30)


### Features

* **content:** offer note i18n translations, restructure content management system ([#35](https://github.com/zaneriley/personal-site/issues/35)) ([a36042b](https://github.com/zaneriley/personal-site/commit/a36042b2477a24d6b5619003acf87478e3fb83d7))

## [0.1.1-alpha.1](https://github.com/zaneriley/personal-site/compare/v0.1.0-alpha.1...v0.1.1-alpha.1) (2024-07-11)


### Miscellaneous

* **release:** bump version to 0.1.0-alpha.2 ([#31](https://github.com/zaneriley/personal-site/issues/31)) ([dbd011d](https://github.com/zaneriley/personal-site/commit/dbd011d80bdb9f731dc2dc11af954dffea08d243))

## 0.1.0-alpha.1 (2024-07-04)

* This commit replaces the entire React-based famichat  with the new Elixir and Phoenix based famichat

### Features

* **ci:** integrate Coveralls for test coverage reporting ([#20](https://github.com/zaneriley/personal-site/issues/20)) ([8f27d2d](https://github.com/zaneriley/personal-site/commit/8f27d2d9b349d6db96e328e2ab45eef70b58d921))
* **ci:** integrate sobelow security checks ([#23](https://github.com/zaneriley/personal-site/issues/23)) ([20dc6cf](https://github.com/zaneriley/personal-site/commit/20dc6cfd1676de374ef89392a93303e8de0c5881))
* **lang-switcher:** resolve conflicts favoring local implementation ([65a1fd6](https://github.com/zaneriley/personal-site/commit/65a1fd612134b2246579417979694e0da34b1a1a))
* merge new Elixir-based famichat, replacing React version ([3e9ac76](https://github.com/zaneriley/personal-site/commit/3e9ac76c478d5eb4ecfa21a825ba1a0cd803bebc))
* **nav:** implement nav as liveview, with lang switcher, url-based routing.  ([#24](https://github.com/zaneriley/personal-site/issues/24)) ([7d47b8a](https://github.com/zaneriley/personal-site/commit/7d47b8aa69f06009de8e31e73cee615dd1cf6b7c))
* **security:** implement content security policy ([cc789a9](https://github.com/zaneriley/personal-site/commit/cc789a98f4a3e0ee194feb70a42f5792c3a00bf8))
* **versioning:** initialize project version ([be7f00b](https://github.com/zaneriley/personal-site/commit/be7f00b712772de73551c041ed2d75534b9b17bb))


### Bug Fixes

* **csp:** use lowercase header names for content security policy ([8925030](https://github.com/zaneriley/personal-site/commit/8925030aad6a8dbc5111ac32a3d095bdd56fcbf0))
* **lefthook:** change elixir format check to format action ([4d9d939](https://github.com/zaneriley/personal-site/commit/4d9d93963fbc3442803163fde3c5d1d6403ac938))


### Documentation

* add moduledocs and improve code documentation ([b406206](https://github.com/zaneriley/personal-site/commit/b4062060f8dc5ab733ef0d3a06fc3c3dc2878d3e))
* **readme:** add work in progress badge and refine project description ([94208aa](https://github.com/zaneriley/personal-site/commit/94208aa53f04bac7123fcb21c38e9d599799158c))
* update license and usage terms in README ([b20c76b](https://github.com/zaneriley/personal-site/commit/b20c76b49e2dcfe98677f041b3e668c94abae0a0))


### Miscellaneous

* **ci:** Modify config for release please ([2a43a13](https://github.com/zaneriley/personal-site/commit/2a43a13219ee65236b449b274b279775d43fe959))
* **readme:** clarify project ([#28](https://github.com/zaneriley/personal-site/issues/28)) ([07c41ad](https://github.com/zaneriley/personal-site/commit/07c41ad8c8065c21db5485cb0a1de55e4ee9b9bf))
* **readme:** fix coverage badge to reflect main branch ([425b8e1](https://github.com/zaneriley/personal-site/commit/425b8e1bc489bd0660dfc2bf1635ecbe78216270))
* **release:** configure pre-1.0 versioning ([e2958f5](https://github.com/zaneriley/personal-site/commit/e2958f524f29d586cb00a8ae69f786b3d7eaa817))
* **release:** configure release-please ([1ce5ffb](https://github.com/zaneriley/personal-site/commit/1ce5ffb3db1f3dded79c939382e99467f7a18264))

## [0.1.0] - 2024-06-27

- Initial release
