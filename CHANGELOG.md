# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Channels: `[:phoenix, :channel_joined]` attributes a channel process to the owner
  whose header the socket's `connect/3` kept in `socket.assigns.phoenix_ecto_sandbox`,
  as phoenix_ecto's channel setup does, so the callbacks after `join/3` are attributed.

### Fixed

- A connected LiveView that defines no `mount/3` and has no `on_mount` hooks, for which
  LiveView emits no mount event, is now attributed from its first `handle_params/3` or
  render.

## [0.1.0] - 2026-10-03

Initial release.

### Added

- `Mutare.Phoenix.Ecto`, a Mutare coverage-attribution extension. Listed under
  `:extensions`, it attributes each request and LiveView carrying phoenix_ecto's SQL
  sandbox metadata to the test that sent it, so a mutant only browser-driven tests reach
  runs those tests instead of the whole suite. It reads Phoenix, LiveView and Bandit
  telemetry, so the endpoint and LiveViews need no change.

[Unreleased]: https://github.com/foxbenjaminfox/mutare_phoenix_ecto/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/foxbenjaminfox/mutare_phoenix_ecto/releases/tag/v0.1.0
