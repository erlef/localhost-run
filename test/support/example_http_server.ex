defmodule LocalhostRun.ExampleHttpServer do
  @moduledoc false

  @behaviour Plug

  import Plug.Conn

  @impl Plug
  def init(_opts), do: []

  @impl Plug
  def call(conn, _opts) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, "Hello, World!")
  end
end
