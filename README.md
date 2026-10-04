# mutare_phoenix_ecto

[![Hex.pm](https://img.shields.io/hexpm/v/mutare_phoenix_ecto.svg)](https://hex.pm/packages/mutare_phoenix_ecto)
[![Hexdocs](https://img.shields.io/badge/hexdocs-docs-blue.svg)](https://hexdocs.pm/mutare_phoenix_ecto)
[![CI](https://github.com/foxbenjaminfox/mutare_phoenix_ecto/actions/workflows/ci.yml/badge.svg?branch=master)](https://github.com/foxbenjaminfox/mutare_phoenix_ecto/actions/workflows/ci.yml)
[![License](https://img.shields.io/hexpm/l/mutare_phoenix_ecto.svg)](https://github.com/foxbenjaminfox/mutare_phoenix_ecto/blob/master/LICENSE)

Test selection for browser-driven tests in [Mutare](https://hexdocs.pm/mutare), the
mutation-testing tool, from the SQL sandbox metadata
[phoenix_ecto](https://hexdocs.pm/phoenix_ecto) already reads.

Mutare runs each mutant against only the tests that executed its line. It finds that
test from the process the line ran in: the test itself, or a process the test started.
A browser-driven test (Wallaby, Hound, Playwright) sends requests that the web server
handles in processes the test did not start, so every mutant only such tests reach runs
the whole suite.

A project that runs those tests concurrently already tells each request which test sent
it: the test encodes its sandbox owner into the request, and `Phoenix.Ecto.SQL.Sandbox`
decodes it to allow the request into that owner's database connection. This package
reads the same metadata during Mutare's coverage run and tells Mutare the owner, which
narrows each mutant the request reaches to the test that sent it.

This package defines no mutators; it only changes which tests run each mutant.

## Install

`mix igniter.install mutare` adds it, and lists it in `.mutare.exs`, for a project that
depends on `phoenix_ecto`. By hand, add it as a dev/test dependency:

```elixir
def deps do
  [
    {:mutare, "~> 0.5.0", only: [:dev, :test], runtime: false},
    {:mutare_phoenix_ecto, "~> 0.1", only: [:dev, :test], runtime: false}
  ]
end
```

and list it under `:extensions` in `.mutare.exs`:

```elixir
[extensions: [Mutare.Phoenix.Ecto]]
```

That is all. The endpoint, router, LiveViews and channels stay as phoenix_ecto's setup
has them: its plug at the top of the endpoint; for LiveView, the socket passing the user
agent (or the `x-` header the plug reads) in its `connect_info`; for channels, the
socket's `connect/3` keeping that header in `socket.assigns.phoenix_ecto_sandbox`.
Mutare attaches this package's `:telemetry` handlers in its coverage run only, so a
plain `mix test` runs none of it.

## What it covers, and what it doesn't

- **Requests, LiveViews and channels carrying sandbox metadata.** Each is attributed to
  the test whose owner the metadata names, while that test is running. A process that
  serves several requests in turn (a keep-alive connection) is attributed to each
  request's test in turn, and to no test during a request that carries no metadata.
  Tasks they start follow them.
- **Shared sandbox mode.** A test in shared mode sends no metadata, so its requests are
  attributed to no test, and their mutants still run the whole suite. That is slow but
  correct: attributing them to whichever test holds the shared connection would also
  claim the work of background processes that happen to run then.
- **Endpoint plugs ahead of `Plug.Telemetry`.** They run before any event that names the
  owner, so their lines stay attributed to no test.
- **Socket connects and channel joins.** A socket's `connect/3` and `id/1` run in the
  connection's process, which the endpoint hands to the socket ahead of its plugs, so no
  event there names the owner; this holds for LiveView's socket too. No event fires in a
  channel process before `join/3` either. So the lines `connect/3`, `id/1` and `join/3`
  run stay attributed to no test. The callbacks after `join/3` are attributed to the
  owner, provided the socket keeps the header in `socket.assigns.phoenix_ecto_sandbox`,
  as phoenix_ecto's channel setup does.
- **Processes the request only calls.** A `GenServer` the request calls runs in its own
  process, which no metadata reaches, so its lines stay attributed to no test, as they
  would in a test that calls it directly.

## How it works

Mutare calls `Mutare.Phoenix.Ecto.attach_attribution/1` in its coverage run, after the
project's test helper. It attaches handlers to events Phoenix, LiveView and Bandit emit
in the process doing the work, each before the application code that event precedes:

- `[:phoenix, :endpoint, :start]` and `[:phoenix, :router_dispatch, :start]` decode the
  header phoenix_ecto's plug read (it keeps it in `conn.assigns.phoenix_ecto_sandbox`)
  and declare its owner, or withdraw the previous request's for a request without one.
- `[:bandit, :request, :start]` withdraws the declaration before the endpoint runs, for
  a connection configured with `clear_process_dict: false`.
- `[:phoenix, :live_view, :mount, :start]`, `[:phoenix, :live_view, :handle_params, :start]`
  and `[:phoenix, :live_view, :render, :start]`, whichever a connected LiveView emits
  first, declare the owner its `connect_info` names, or, for a nested LiveView with none,
  its parent. (LiveView emits the mount event only for a view that defines `mount/3` or
  has `on_mount` hooks.)
- `[:phoenix, :channel_joined]` declares the owner whose header the socket's `connect/3`
  kept in `socket.assigns.phoenix_ecto_sandbox`, once `join/3` returns.

The declaration is
[`Mutare.CoverageAttribution.attribute_to/1`](https://hexdocs.pm/mutare/Mutare.CoverageAttribution.html#attribute_to/1).
The owner it names — usually the process `Ecto.Adapters.SQL.Sandbox.start_owner!/2`
started — leads Mutare back to the test that started it.
