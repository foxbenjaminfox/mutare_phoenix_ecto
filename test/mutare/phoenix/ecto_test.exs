defmodule Mutare.Phoenix.EctoTest do
  # The handlers are attached once for the VM (`test_helper.exs`, as Mutare's probe does), and
  # each test drives real requests or LiveViews through the test endpoint.
  use ExUnit.Case, async: true

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Mutare.Phoenix.Ecto.Test.Owners

  alias Mutare.Phoenix.Ecto.Test.Endpoint

  @endpoint Endpoint

  describe "a request served by Bandit" do
    test "carrying an owner's metadata is attributed to that owner" do
      owner = owner()

      # From `Plug.Telemetry` on: the plugs ahead of it run before any event names the owner.
      assert [%{early: nil, endpoint: ^owner, declared: ^owner}] =
               on_one_connection([metadata(owner)])
    end

    test "without metadata declares nothing" do
      assert [%{early: nil, declared: nil}] = on_one_connection([nil])
    end

    test "without metadata, after one with it on the same connection, is attributed to no owner" do
      # Bandit serves a keep-alive connection's requests in one process; the earlier request's
      # owner is withdrawn before the endpoint runs, not only once `Plug.Telemetry` does.
      owner = owner()

      assert [%{pid: pid, declared: ^owner}, %{pid: pid, early: nil, declared: nil}] =
               on_one_connection([metadata(owner), nil])
    end

    test "after another on the same connection is attributed to its own owner" do
      first = owner()
      second = owner()

      assert [%{pid: pid, declared: ^first}, %{pid: pid, early: nil, declared: ^second}] =
               on_one_connection([metadata(first), metadata(second)])
    end
  end

  describe "a LiveView" do
    test "connected with an owner's metadata is attributed to that owner" do
      owner = owner()

      conn = Plug.Conn.put_req_header(build_conn(), "user-agent", metadata(owner))
      {:ok, view, _html} = live(conn, "/live")

      assert view |> element("#parent-declared") |> render() =~ escaped(owner)
    end

    test "nested without metadata of its own is attributed through its parent" do
      # `Phoenix.LiveViewTest` gives a nested LiveView an empty `connect_info`, where a browser's
      # websocket would share its parent's.
      conn = Plug.Conn.put_req_header(build_conn(), "user-agent", metadata(owner()))
      {:ok, view, _html} = live(conn, "/live")

      assert view |> find_live_child("child") |> element("#child-declared") |> render() =~
               escaped(view.pid)
    end

    test "connected without metadata declares no owner, and a nested one only its parent" do
      {:ok, view, _html} = live(build_conn(), "/live")

      assert view |> element("#parent-declared") |> render() =~ "nil"

      assert view |> find_live_child("child") |> element("#child-declared") |> render() =~
               escaped(view.pid)
    end

    test "rendered again after connecting stays attributed and leaves every handler attached" do
      # LiveView drops `connect_info` once the first render is done; a later render event that
      # read it would raise, and `:telemetry` detaches a handler that raises.
      owner = owner()

      conn = Plug.Conn.put_req_header(build_conn(), "user-agent", metadata(owner))
      {:ok, view, _html} = live(conn, "/live")

      assert render_click(view, "rerender") =~ ~s(<p id="renders">1</p>)
      assert view |> element("#parent-declared") |> render() =~ escaped(owner)
      assert handler_ids() == expected_handler_ids()
    end

    test "without mount/3 is attributed from handle_params/3 on" do
      owner = owner()

      conn = Plug.Conn.put_req_header(build_conn(), "user-agent", metadata(owner))
      {:ok, view, _html} = live(conn, "/params")

      assert view |> element("#declared") |> render() =~ escaped(owner)
    end

    test "without mount/3 or handle_params/3 is attributed from render/1 on" do
      owner = owner()

      conn = Plug.Conn.put_req_header(build_conn(), "user-agent", metadata(owner))
      {:ok, view, _html} = live(conn, "/render")

      assert view |> element("#declared") |> render() =~ escaped(owner)
    end

    test "rendered dead with a nested LiveView leaves every handler attached" do
      # The nested LiveView's dead render has no `connect_info`; reading it would raise, and
      # `:telemetry` detaches a handler that raises.
      owner = owner()

      conn =
        build_conn()
        |> Plug.Conn.put_req_header("user-agent", metadata(owner))
        |> get("/live")

      assert conn.status == 200
      assert handler_ids() == expected_handler_ids()
    end

    test "rendered dead keeps the request's attribution, not the owner its connect_info names" do
      # A dead render's `connect_info` is the request, whose `x-` headers a connected LiveView
      # would read; the sandbox plug reads only the user agent, so it found no owner here.
      conn =
        build_conn()
        |> Plug.Conn.put_req_header("x-sandbox", metadata(owner()))
        |> get("/live")

      assert html_response(conn, 200) =~ ~s(<p id="parent-declared">nil</p>)
    end
  end

  describe "attach_attribution/1" do
    test "attaches each handler once however often it is called" do
      assert Mutare.Phoenix.Ecto.attach_attribution([]) == :ok
      assert handler_ids() == expected_handler_ids()
    end
  end

  defp escaped(term),
    do: term |> inspect() |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

  # Each user agent's request in turn over one keep-alive connection, decoded to what the probe
  # route replied. `:httpc` reuses a session for sequential requests; the replies' `pid`s show
  # whether it did.
  defp on_one_connection(user_agents) do
    {:ok, _} = Application.ensure_all_started(:inets)
    profile = :"mutare_phoenix_ecto_#{System.unique_integer([:positive])}"
    {:ok, client} = :inets.start(:httpc, profile: profile)
    on_exit(fn -> :inets.stop(:httpc, client) end)
    :ok = :httpc.set_options([max_sessions: 1, max_keep_alive_length: 10], profile)
    {:ok, {_ip, port}} = Endpoint.server_info(:http)
    url = ~c"http://127.0.0.1:#{port}/probe"

    for user_agent <- user_agents do
      headers = if user_agent, do: [{~c"user-agent", String.to_charlist(user_agent)}], else: []

      {:ok, {{_, 200, _}, _headers, body}} =
        :httpc.request(:get, {url, headers}, [], [body_format: :binary], profile)

      body |> Base.decode64!() |> :erlang.binary_to_term()
    end
  end

  defp handler_ids do
    Enum.sort(for %{id: {Mutare.Phoenix.Ecto, _} = id} <- :telemetry.list_handlers([]), do: id)
  end

  defp expected_handler_ids do
    # One id per `attach_many/4`, listed once per event it covers.
    Enum.sort([
      {Mutare.Phoenix.Ecto, :server_request},
      {Mutare.Phoenix.Ecto, :phoenix_request},
      {Mutare.Phoenix.Ecto, :phoenix_request},
      {Mutare.Phoenix.Ecto, :channel_join},
      {Mutare.Phoenix.Ecto, :live_view},
      {Mutare.Phoenix.Ecto, :live_view},
      {Mutare.Phoenix.Ecto, :live_view}
    ])
  end
end
