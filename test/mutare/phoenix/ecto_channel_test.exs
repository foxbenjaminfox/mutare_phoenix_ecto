defmodule Mutare.Phoenix.EctoChannelTest do
  # Separate from `Mutare.Phoenix.EctoTest`, whose `Phoenix.ConnTest` and `Phoenix.LiveViewTest`
  # imports clash with `Phoenix.ChannelTest`'s.
  use ExUnit.Case, async: true

  import Phoenix.ChannelTest
  import Mutare.Phoenix.Ecto.Test.Owners

  alias Mutare.Phoenix.Ecto.Test.ProbeSocket

  @endpoint Mutare.Phoenix.Ecto.Test.Endpoint

  describe "a channel" do
    test "joined with an owner's metadata is attributed to that owner after join/3" do
      owner = owner()

      {:ok, socket} = connect(ProbeSocket, %{}, connect_info: %{user_agent: metadata(owner)})
      # Phoenix emits the event only once `join/3` returns.
      {:ok, %{declared: nil}, socket} = join(socket, "probe")

      ref = push(socket, "declared", %{})
      assert_reply ref, :ok, %{declared: ^owner}
    end

    test "joined without metadata declares no owner and leaves its handler attached" do
      {:ok, socket} = connect(ProbeSocket, %{}, connect_info: %{user_agent: nil})
      {:ok, _reply, socket} = join(socket, "probe")

      ref = push(socket, "declared", %{})
      assert_reply ref, :ok, %{declared: nil}

      # `declared: nil` is also what a handler that never ran leaves; one that raised on the
      # missing header shows instead in `:telemetry` detaching it, before `join/3` replied.
      assert {Mutare.Phoenix.Ecto, :channel_join} in handler_ids()
    end
  end

  defp handler_ids do
    for %{id: id} <- :telemetry.list_handlers([:phoenix, :channel_joined]), do: id
  end
end
