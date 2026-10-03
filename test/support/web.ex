defmodule Mutare.Phoenix.Ecto.Test.Probe do
  @moduledoc false
  # What the tests read back: the owner the process declared to Mutare, under the key
  # `Mutare.CoverageAttribution.attribute_to/1` writes and the coverage probe reads.
  @anchor_key Mutare.Coverage.Recorder.runtime(:harness).anchor_key

  def declared, do: Process.get(@anchor_key)
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

  def mount(_params, _session, socket), do: {:ok, assign(socket, declared: Probe.declared())}

  def render(assigns) do
    ~H"""
    <p id="parent-declared">{inspect(@declared)}</p>
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
