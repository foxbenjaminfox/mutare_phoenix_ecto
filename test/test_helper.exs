alias Mutare.Phoenix.Ecto.Test.{Endpoint, Repo}

database =
  Path.join(System.tmp_dir!(), "mutare_phoenix_ecto_#{System.unique_integer([:positive])}.db")

Application.put_env(:mutare_phoenix_ecto, Repo,
  database: database,
  pool: Ecto.Adapters.SQL.Sandbox,
  log: false
)

Application.put_env(:mutare_phoenix_ecto, Endpoint,
  adapter: Bandit.PhoenixAdapter,
  # Bandit clears a keep-alive connection's process dictionary between requests unless told not
  # to, which withdraws a declaration on its own; the withdrawal under test is the one that
  # holds without it.
  http: [ip: {127, 0, 0, 1}, port: 0, http_1_options: [clear_process_dict: false]],
  server: true,
  secret_key_base: String.duplicate("mutare-phoenix-ecto", 4),
  live_view: [signing_salt: "mutare-phoenix-ecto"],
  check_origin: false
)

Application.put_env(:phoenix, :json_library, Jason)
Logger.configure(level: :warning)

{:ok, _} = Repo.start_link()
Ecto.Adapters.SQL.Sandbox.mode(Repo, :manual)
{:ok, _} = Endpoint.start_link()

# What Mutare's coverage probe does after the project's own helper.
:ok = Mutare.Phoenix.Ecto.attach_attribution([])

ExUnit.after_suite(fn _result ->
  for suffix <- ["", "-shm", "-wal"], do: File.rm(database <> suffix)
end)

ExUnit.start()
