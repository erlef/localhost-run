defmodule LocalhostRunTest do
  use ExUnit.Case, async: true

  doctest LocalhostRun

  setup do
    port = discover_free_port()

    start_supervised!({Bandit, plug: LocalhostRun.ExampleHttpServer, port: port, ip: :any})

    {:ok, http_port: port}
  end

  describe inspect(&LocalhostRun.start_link/1) do
    test "starts a GenServer", %{http_port: http_port} do
      assert {:ok, pid} = LocalhostRun.start_link(internal_port: http_port, name: StartLink)

      assert host = LocalhostRun.get_exposed_host(pid)

      assert %Req.Response{status: 200} = Req.get!("https://#{host}/")

      assert :ok = GenServer.stop(pid)
    end

    test "error on invalid ssh host", %{http_port: http_port} do
      Process.flag(:trap_exit, true)

      assert {:error, :nxdomain} =
               LocalhostRun.start_link(internal_port: http_port, name: StartLinkInvalid, ssh_host: "invalid")
    end
  end

  describe inspect(&LocalhostRun.child_spec/1) do
    test "gives a unique id" do
      child_spec = LocalhostRun.child_spec(internal_port: 1234, name: ChildSpec)

      assert child_spec.id == {LocalhostRun, ChildSpec, "localhost->1234"}
    end
  end

  describe inspect(&LocalhostRun.get_exposed_host/1) do
    test "returns the host", %{http_port: http_port} do
      start_supervised!({LocalhostRun, internal_port: http_port, name: ExposedHost})

      # Waits for the host to be available
      assert host = LocalhostRun.get_exposed_host(ExposedHost)
      # When already available
      assert host == LocalhostRun.get_exposed_host(ExposedHost)

      assert is_binary(host)
    end
  end

  describe inspect(&LocalhostRun.connect/1) do
    test "allows manual connection", %{http_port: http_port} do
      assert {:ok, {conn_ref, channel_id}} = LocalhostRun.connect(internal_port: http_port)

      assert_receive {:ssh_cm, ^conn_ref, {:data, ^channel_id, 0, _message}}

      assert :ok = :ssh_connection.close(conn_ref, channel_id)
      assert :ok = :ssh.close(conn_ref)
    end

    test "error with missing options" do
      assert {:error, {:missing_required_option, [:internal_port]}} = LocalhostRun.connect([])
    end

    test "error with unknown options" do
      assert {:error, {:unknown_option, [:foo]}} = LocalhostRun.connect(foo: :bar)
    end
  end

  defp discover_free_port do
    {:ok, listen} = :gen_tcp.listen(0, [])
    {:ok, port} = :inet.port(listen)

    :gen_tcp.close(listen)

    port
  end
end
