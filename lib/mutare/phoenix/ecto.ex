defmodule Mutare.Phoenix.Ecto do
  @moduledoc """
  Tells Mutare which test sent each request in a browser-driven test, from the SQL
  sandbox metadata the request already carries.

  Mutare runs each mutant against only the tests that executed its line. It finds
  the test from the process the line ran in: the test process itself, or a process
  it started. A browser-driven test (Wallaby, Hound, Playwright) sends requests
  that the web server handles in processes the test did not start, so a mutant only
  such tests reach runs the whole suite.

  A project that runs those tests concurrently already says which test sent each
  request: the test encodes its sandbox owner into the request (the user agent, by
  default), and `Phoenix.Ecto.SQL.Sandbox` decodes it to allow the request into
  that owner's database connection. This extension reads the same metadata and
  declares the owner to Mutare (`Mutare.CoverageAttribution.attribute_to/1`).

  ## Setup

  List it under `:extensions` in `.mutare.exs`; `mix igniter.install mutare` does
  this for a project that depends on `phoenix_ecto`:

      [extensions: [Mutare.Phoenix.Ecto]]

  Nothing in the endpoint, router, or LiveViews changes. Mutare attaches the
  extension's `:telemetry` handlers in its coverage probe and nowhere else, so a
  plain `mix test` runs none of this.

  ## Where it reads the metadata

  Each handler runs in the process doing the work, before the application's code
  in it:

    * `[:phoenix, :endpoint, :start]` (from `Plug.Telemetry` in the endpoint) and
      `[:phoenix, :router_dispatch, :start]` (before the route's pipelines) declare
      the owner whose metadata `Phoenix.Ecto.SQL.Sandbox` found in the request, or
      withdraw the declaration for a request that carries none. The plug keeps the
      header it read in `conn.assigns.phoenix_ecto_sandbox`, so a custom `:header`
      option needs no configuration here.
    * `[:bandit, :request, :start]` withdraws the declaration before the endpoint
      runs at all. Bandit serves a keep-alive connection's requests in one process
      and by default clears its process dictionary between them, which withdraws the
      declaration too; with `clear_process_dict: false`, the endpoint plugs ahead of
      `Plug.Telemetry` would otherwise run under the previous request's owner.
    * `[:phoenix, :live_view, :mount, :start]`, in a connected LiveView, declares
      the owner from its `connect_info`: the user agent, or an `x-` header, as
      phoenix_ecto's LiveView setup requires the socket to pass. A nested LiveView
      whose `connect_info` names no owner — `Phoenix.LiveViewTest` gives one an
      empty `connect_info` — declares its parent, whose test it works for. A dead
      render runs in the request process, whose handlers above have already
      declared.

  ## What it covers, and what it doesn't

    * **Requests and LiveViews carrying sandbox metadata** are attributed to the
      test whose owner the metadata names, while that test is running. Tasks they
      start follow them.
    * **Shared sandbox mode.** A test in shared mode sends no metadata, so its
      requests are attributed to no test, and their mutants still run the whole
      suite. That is slow but correct: attributing them to whichever test holds the
      shared connection would also claim the work of background processes that
      happen to run then.
    * **Channels.** No event fires in a channel process before `join/3`, so lines
      a join runs stay attributed to no test.
    * **Processes the request only calls.** A `GenServer` the request calls runs
      in its own process, which no metadata reaches, so its lines stay attributed
      to no test, as they would in a test that calls it directly.
  """

  @behaviour Mutare.CoverageAttribution

  alias Mutare.CoverageAttribution
  alias Phoenix.Ecto.SQL.Sandbox

  @doc """
  Attaches the `:telemetry` handlers described above. Mutare calls it in the
  coverage probe; a second call leaves them attached once.
  """
  @impl CoverageAttribution
  def attach_attribution(_opts) do
    attach(:server_request, [[:bandit, :request, :start]], &__MODULE__.withdraw/4)

    attach(
      :phoenix_request,
      [[:phoenix, :endpoint, :start], [:phoenix, :router_dispatch, :start]],
      &__MODULE__.declare_request/4
    )

    attach_live_view()
  end

  defp attach(name, events, handler) do
    case :telemetry.attach_many({__MODULE__, name}, events, handler, nil) do
      :ok -> :ok
      {:error, :already_exists} -> :ok
    end
  end

  @doc false
  def withdraw(_event, _measurements, _metadata, _config),
    do: CoverageAttribution.attribute_to(nil)

  @doc false
  def declare_request(_event, _measurements, %{conn: conn}, _config) do
    conn.assigns
    |> Map.get(:phoenix_ecto_sandbox)
    |> owner()
    |> CoverageAttribution.attribute_to()
  end

  # LiveView is an optional dependency: a project without it has no mount event to handle.
  if Code.ensure_loaded?(Phoenix.LiveView) do
    defp attach_live_view do
      attach(
        :live_view_mount,
        [[:phoenix, :live_view, :mount, :start]],
        &__MODULE__.declare_live_view/4
      )
    end

    @doc false
    # Only a connected mount: every one carries `connect_info`, while a nested LiveView in a
    # dead render may not, where `get_connect_info/2` raises and `:telemetry` would detach the
    # handler for the rest of the run.
    def declare_live_view(_event, _measurements, %{socket: socket}, _config) do
      with true <- Phoenix.LiveView.connected?(socket),
           owner when is_pid(owner) <- connect_info_owner(socket) || socket.parent_pid do
        CoverageAttribution.attribute_to(owner)
      else
        _ -> :ok
      end
    end

    defp connect_info_owner(socket) do
      x_headers = Phoenix.LiveView.get_connect_info(socket, :x_headers) || []

      [Phoenix.LiveView.get_connect_info(socket, :user_agent) | Enum.map(x_headers, &elem(&1, 1))]
      |> Enum.find_value(&owner/1)
    end
  else
    defp attach_live_view, do: :ok
  end

  defp owner(encoded) do
    case Sandbox.decode_metadata(encoded) do
      %{owner: owner} when is_pid(owner) -> owner
      _ -> nil
    end
  end
end
