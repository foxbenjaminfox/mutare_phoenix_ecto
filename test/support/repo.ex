defmodule Mutare.Phoenix.Ecto.Test.Repo do
  @moduledoc false
  # A real repo on the real SQL sandbox, so the tests see phoenix_ecto's plug allow a
  # process into an owner's connection, not a stand-in's idea of it.
  use Ecto.Repo, otp_app: :mutare_phoenix_ecto, adapter: Ecto.Adapters.SQLite3
end
