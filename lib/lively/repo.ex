defmodule Lively.Repo do
  use Ecto.Repo,
    otp_app: :lively,
    adapter: Ecto.Adapters.SQLite3
end
