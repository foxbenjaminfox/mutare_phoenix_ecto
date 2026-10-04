defmodule Mutare.Phoenix.Ecto.Test.Probe do
  @moduledoc false
  # What the tests read back: the owner the process declared to Mutare, under the key
  # `Mutare.CoverageAttribution.attribute_to/1` writes and the coverage probe reads.
  @anchor_key Mutare.Coverage.Recorder.runtime(:harness).anchor_key

  def declared, do: Process.get(@anchor_key)
end

defmodule Mutare.Phoenix.Ecto.Test.Owners do
  @moduledoc false
  alias Ecto.Adapters.SQL.Sandbox, as: SQLSandbox
  alias Mutare.Phoenix.Ecto.Test.Repo
  alias Phoenix.Ecto.SQL.Sandbox, as: SandboxPlug

  import ExUnit.Callbacks, only: [on_exit: 1]

  # A sandbox owner of the shape a browser-driven test starts, stopped when the test exits.
  def owner do
    owner = Task.async(fn -> SQLSandbox.start_owner!(Repo) end) |> Task.await()
    on_exit(fn -> SQLSandbox.stop_owner(owner) end)
    owner
  end

  # The metadata naming `owner`, as the test's browser sends it.
  def metadata(owner),
    do: Repo |> SandboxPlug.metadata_for(owner) |> SandboxPlug.encode_metadata()
end

defmodule Mutare.Phoenix.Ecto.Test.ProbePlug do
  @moduledoc false
  # The route a request reaches: replies with the serving process, what it had declared
  # before `Plug.Telemetry` ran (`early`), between it and the router (`endpoint`), and at the
  # route, as an encoded term.
  import Plug.Conn

  alias Mutare.Phoenix.Ecto.Test.Probe

  def init(opts), do: opts

  def call(conn, _opts) do
    reply = %{
      pid: self(),
      early: conn.private.early_declared,
      endpoint: conn.private.endpoint_declared,
      declared: Probe.declared()
    }

    send_resp(conn, 200, reply |> :erlang.term_to_binary() |> Base.encode64())
  end
end

defmodule Mutare.Phoenix.Ecto.Test.ParentLive do
  @moduledoc false
  use Phoenix.LiveView

  alias Mutare.Phoenix.Ecto.Test.Probe

  def mount(_params, _session, socket),
    do: {:ok, assign(socket, declared: Probe.declared(), renders: 0)}

  # Changes an assign, so LiveView renders the view again.
  def handle_event("rerender", _params, socket),
    do:
      {:noreply, assign(socket, declared: Probe.declared(), renders: socket.assigns.renders + 1)}

  def render(assigns) do
    ~H"""
    <p id="parent-declared">{inspect(@declared)}</p>
    <p id="renders">{@renders}</p>
    {live_render(@socket, Mutare.Phoenix.Ecto.Test.ChildLive, id: "child")}
    """
  end
end

defmodule Mutare.Phoenix.Ecto.Test.ChildLive do
  @moduledoc false
  use Phoenix.LiveView

  alias Mutare.Phoenix.Ecto.Test.Probe

  def mount(_params, _session, socket), do: {:ok, assign(socket, declared: Probe.declared())}

  def render(assigns) do
    ~H"""
    <p id="child-declared">{inspect(@declared)}</p>
    """
  end
end

defmodule Mutare.Phoenix.Ecto.Test.ParamsLive do
  @moduledoc false
  # No `mount/3`, so LiveView emits no mount event.
  use Phoenix.LiveView

  alias Mutare.Phoenix.Ecto.Test.Probe

  def handle_params(_params, _uri, socket),
    do: {:noreply, assign(socket, declared: Probe.declared())}

  def render(assigns) do
    ~H"""
    <p id="declared">{inspect(@declared)}</p>
    """
  end
end

defmodule Mutare.Phoenix.Ecto.Test.RenderLive do
  @moduledoc false
  # Neither `mount/3` nor `handle_params/3`: render is the only event.
  use Phoenix.LiveView

  alias Mutare.Phoenix.Ecto.Test.Probe

  def render(assigns) do
    ~H"""
    <p id="declared">{inspect(Probe.declared())}</p>
    """
  end
end

defmodule Mutare.Phoenix.Ecto.Test.ProbeChannel do
  @moduledoc false
  # Replies with what the channel process had declared, during `join/3` and at each message.
  use Phoenix.Channel

  alias Mutare.Phoenix.Ecto.Test.Probe

  def join("probe", _payload, socket), do: {:ok, %{declared: Probe.declared()}, socket}

  def handle_in("declared", _payload, socket),
    do: {:reply, {:ok, %{declared: Probe.declared()}}, socket}
end

defmodule Mutare.Phoenix.Ecto.Test.ProbeSocket do
  @moduledoc false
  # Keeps the header where phoenix_ecto's channel setup does. `Phoenix.ChannelTest` connects to it
  # directly, so the endpoint mounts no route to it.
  use Phoenix.Socket

  channel "probe", Mutare.Phoenix.Ecto.Test.ProbeChannel

  def connect(_params, socket, connect_info),
    do: {:ok, assign(socket, :phoenix_ecto_sandbox, connect_info.user_agent)}

  def id(_socket), do: nil
end

defmodule Mutare.Phoenix.Ecto.Test.Router do
  @moduledoc false
  use Phoenix.Router
  import Phoenix.LiveView.Router

  pipeline :browser do
    plug :fetch_session
  end

  scope "/" do
    pipe_through :browser
    get "/probe", Mutare.Phoenix.Ecto.Test.ProbePlug, []
    live "/live", Mutare.Phoenix.Ecto.Test.ParentLive
    live "/params", Mutare.Phoenix.Ecto.Test.ParamsLive
    live "/render", Mutare.Phoenix.Ecto.Test.RenderLive
  end
end

defmodule Mutare.Phoenix.Ecto.Test.Endpoint do
  @moduledoc false
  # The shape a Phoenix app running browser-driven tests has: phoenix_ecto's sandbox plug at
  # the top, `Plug.Telemetry` further down, the router last.
  use Phoenix.Endpoint, otp_app: :mutare_phoenix_ecto

  @session_options [store: :cookie, key: "_probe", signing_salt: "mutare-probe"]

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [:user_agent, session: @session_options]]

  plug Phoenix.Ecto.SQL.Sandbox, repo: Mutare.Phoenix.Ecto.Test.Repo
  # A plug ahead of `Plug.Telemetry`, recording what the request process had declared then.
  plug :record_early
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]
  # And one between `Plug.Telemetry` and the router.
  plug :record_endpoint
  plug Plug.Session, @session_options
  plug Mutare.Phoenix.Ecto.Test.Router

  defp record_early(conn, _opts),
    do: put_private(conn, :early_declared, Mutare.Phoenix.Ecto.Test.Probe.declared())

  defp record_endpoint(conn, _opts),
    do: put_private(conn, :endpoint_declared, Mutare.Phoenix.Ecto.Test.Probe.declared())
end
