defmodule TryElixir.Router do
  @moduledoc false

  use Plug.Router
  use Plug.ErrorHandler
  import Plug.Conn

  @cookie_key "_tryelixir_session"

  plug(Plug.Static, at: "/static", from: :try_elixir)

  plug(Plug.Session,
    store: :cookie,
    key: @cookie_key,
    secret_key_base: Application.fetch_env!(:try_elixir, :secret_key_base),
    encryption_salt: Application.fetch_env!(:try_elixir, :encryption_salt),
    signing_salt: Application.fetch_env!(:try_elixir, :signing_salt)
  )

  plug(:match)
  plug(:dispatch)

  get "/" do
    {:ok, pid} = TryElixir.Sandbox.start()

    conn
    |> fetch_session()
    |> put_session(@cookie_key, pid)
    |> send_resp(200, TryElixir.Template.index())
  end

  get "/about" do
    send_resp(conn, 200, TryElixir.Template.about())
  end

  get "/api/version" do
    send_resp(conn, 200, System.version())
  end

  post "/api/eval" do
    conn = fetch_session(conn)
    pid = get_session(conn, @cookie_key)

    {conn, pid} = if not is_pid(pid) or not Process.alive?(pid) do
      {:ok, pid} = TryElixir.Sandbox.start()
      {put_session(conn, @cookie_key, pid), pid}
    else
      {conn, pid}
    end

    code = "1"
    response = TryElixir.Sandbox.eval(pid, code)

    send_resp(conn, 200, format_response(response))
  end

  match _ do
    send_resp(conn, 404, "Not Found")
  end

  def handle_errors(conn, %{kind: _kind, reason: _reason, stack: _stack}) do
    # TODO log error
    send_resp(conn, conn.status, "Something went wrong")
  end

  defp format_response({:incomplete, line}) do
    ~s/{"prompt": "...(#{line})> "}/
  end

  defp format_response({{:ok, result}, line}) do
    ~s/{"prompt": "iex(#{line})> ", "type": "ok", "result": "#{result}"}/
  end

  defp format_response({{:error, result}, line}) do
    ~s/{"prompt": "iex(#{line})> ", "type": "error", "result": "#{result}"}/
  end
end
