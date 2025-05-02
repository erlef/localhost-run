defmodule LocalhostRun do
  @moduledoc ~S"""
  Elixir client for localhost.run

  ## Usage

  <!-- tabs-open -->

  ### Via `GenServer`

  ```elixir
  {:ok, pid} = LocalhostRun.start_link(internal_port: 4000)
  ```

  ### Via `Supervisor`

  ```elixir
  children = [
    {LocalhostRun, [internal_port: 4000]}
  ]
  opts = [strategy: :one_for_one, name: MyApp.Supervisor]
  Supervisor.start_link(children, opts)
  ```

  ### Direct

  ```elixir
  {:ok, {conn_ref, channel_id}} = LocalhostRun.connect(internal_port: 4000)

  receive do
    {:ssh_cm, ^conn_ref, {:data, ^channel_id, 0, message}} ->
      case JSON.decode!(message) do
        %{"event" => "tcpip-forward", "address" => host} ->
          Logger.info("Tunnel established to #{host}")
          {:ok, host}

        %{"event" => "authn", "message" => message} ->
          Logger.info("Tunnel authentication successful: #{message}")
          :ok

        %{"message" => message} ->
          Logger.debug("Received message from SSH channel on STDOUT: #{inspect(message)}")
      end
  end
  ```

  <!-- tabs-close -->

  ## Login to localhost.run

  If you want custom domain names or longer lasting tunnels, you need to login
  to localhost.run.

  See: https://localhost.run/docs/custom-domains

  To do so, you have the following options:

  <!-- tabs-open -->

  ### Use SSH Agent

  To use your SSH agent, ensure that it is running and that you have added your
  SSH key to it. You can verify that your SSH agent is running by running the
  following command:

  ```bash
  ssh-add -l
  ```
  If you see a list of keys, your SSH agent is running. If not, you can start it by running:

  ```bash
  eval "$(ssh-agent -s)"
  ```

  Then, add your SSH key to the agent:

  ```bash
  ssh-add ~/.ssh/id_rsa
  ```

  Afterwards you can use the `LocalhostRun` module with the `:ssh_options` option
  to specify the SSH agent:

  ```elixir
  {:ok, pid} = LocalhostRun.start_link(internal_port: 4000, ssh_options: [
    user: "your_username",
    key_cb: {:ssh_agent, []}
  ])
  ```

  Check the [`ssh_agent`] documentation for more information.

  ### Use SSH Key

  If you want to use a specific SSH key, you can specify to use the `key_cb`
  `ssh_file` in the `:ssh_options` option:

  ```elixir
  {:ok, pid} = LocalhostRun.start_link(internal_port: 4000, ssh_options: [
    user: "your_username",
    key_cb: {:ssh_file, []}
  ])
  ```

  Check the `ssh_file` documentation for more information.

  <!-- tabs-close -->

  ## Logger Metadata

  The `LocalhostRun` module automatically sets the following metadata for the
  `Logger` module:

  - `ssh_host` - The SSH host to connect to.
  - `ssh_port` - The SSH port to connect to.
  - `external_host` - The external host to use for the tunnel.
  - `internal_port` - The internal port to forward.
  """

  use GenServer

  require Logger

  @enforce_keys [:conn_ref, :channel_id]
  defstruct [:conn_ref, :channel_id, host: nil, waiting: []]

  @default_name __MODULE__
  @default_ssh_host "localhost.run"
  @default_ssh_port 22
  @default_external_host "localhost"
  @default_connect_timeout to_timeout(second: 10)

  @typedoc """
  Options for the `LocalhostRun` GenServer.

  - `:name` - The name of the GenServer process. Default is `LocalhostRun`.
  - `:ssh_host` - The SSH host to connect to. Default is `localhost.run`.
  - `:ssh_port` - The SSH port to connect to. Default is `22`.
  - `:external_host` - The external host to use for the tunnel. Default is a random host.
  - `:ssh_options` - Additional SSH options. Default is an empty list.
  - `:connect_timeout` - The timeout for the SSH connection. Default is `10` seconds.
  - `:internal_port` - The internal port to forward. This is required and should be provided.
  """
  @type opts :: [
          name: GenServer.name(),
          ssh_host: String.t(),
          ssh_port: :inet.port_number(),
          external_host: String.t(),
          ssh_options: :ssh.client_options(),
          connect_timeout: timeout(),
          internal_port: :inet.port_number()
        ]

  @typep internal_opts :: %{
           required(:internal_port) => :inet.port_number(),
           required(:name) => GenServer.name(),
           required(:ssh_host) => String.t(),
           required(:ssh_port) => :inet.port_number(),
           optional(:external_host) => String.t(),
           required(:ssh_options) => :ssh.client_options(),
           required(:connect_timeout) => timeout()
         }

  @doc """
  Starts the `LocalhostRun` GenServer.

  It connects to the SSH server and sets up the tunnel.

  The `:internal_port` option is required and should be provided.
  """
  def start_link(opts) do
    with {:ok, {init_opts, start_opts}} <- default_opts(opts) do
      GenServer.start_link(__MODULE__, init_opts, start_opts)
    end
  end

  @doc false
  def child_spec(opts) do
    {:ok, {init_opts, start_opts}} = default_opts(opts)

    child_spec = super(opts)

    %{
      child_spec
      | id: {child_spec.id, start_opts[:name], "#{init_opts[:external_host]}->#{init_opts[:internal_port]}"}
    }
  end

  @doc false
  @impl GenServer
  def init(opts) do
    case _connect(opts) do
      {:ok, {conn_ref, channel_id}} ->
        Logger.metadata(
          ssh_host: opts[:ssh_host],
          ssh_port: opts[:ssh_port],
          external_host: opts[:external_host],
          internal_port: opts[:internal_port]
        )

        true = Process.link(conn_ref)

        Process.set_label(__MODULE__)

        {:ok, %__MODULE__{conn_ref: conn_ref, channel_id: channel_id}}

      {:error, reason} ->
        Logger.error("Failed to connect to SSH server: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @doc false
  @impl GenServer
  def handle_info(
        {:ssh_cm, conn_ref, {:data, channel_id, 0, message}},
        %__MODULE__{conn_ref: conn_ref, channel_id: channel_id} = state
      ) do
    decoded = JSON.decode!(message)

    Logger.metadata(tunnel_connection_id: decoded["connection_id"])

    case decoded do
      %{"event" => "tcpip-forward", "address" => host} ->
        Logger.info("Tunnel established to #{host}")

        Logger.metadata(external_host: host)

        Process.set_label({__MODULE__, host})

        Enum.each(state.waiting, &GenServer.reply(&1, host))

        {:noreply, %{state | host: host, waiting: []}}

      %{"event" => "authn", "message" => message} ->
        Logger.info("Tunnel authentication successful: #{message}")

        {:noreply, state}

      %{"message" => message} ->
        # coveralls-ignore-start This will only trigger in localhost.run
        # introduces new message types
        Logger.debug("Received message from SSH channel on STDOUT: #{inspect(message)}")

        {:noreply, state}
        # coveralls-ignore-stop
    end
  end

  # coveralls-ignore-start Can't produce the ignores messages on purpose
  def handle_info(
        {:ssh_cm, conn_ref, {:data, channel_id, 1, message}},
        %__MODULE__{conn_ref: conn_ref, channel_id: channel_id} = state
      ) do
    Logger.error("Received message from SSH channel on STDERR: #{inspect(message)}")
    {:noreply, state}
  end

  def handle_info(
        {:ssh_cm, conn_ref, {:eof, channel_id}},
        %__MODULE__{conn_ref: conn_ref, channel_id: channel_id} = state
      ) do
    Logger.info("SSH: EOF received")
    {:noreply, state}
  end

  def handle_info(
        {:ssh_cm, conn_ref, {:exit_status, channel_id, status}},
        %__MODULE__{conn_ref: conn_ref, channel_id: channel_id} = state
      ) do
    Logger.info("SSH: Exit status #{status}")
    {:noreply, state}
  end

  def handle_info(
        {:ssh_cm, conn_ref, {:closed, channel_id}},
        %__MODULE__{conn_ref: conn_ref, channel_id: channel_id} = state
      ) do
    Logger.info("SSH: Channel closed")
    {:stop, :normal, %{state | host: nil, channel_id: nil}}
  end

  def handle_info({:ssh_cm, conn_ref, msg}, %__MODULE__{conn_ref: conn_ref} = state) do
    Logger.warning("Unhandled SSH message: #{inspect(msg)}")
    {:noreply, state}
  end

  # coveralls-ignore-stop

  @impl GenServer
  def handle_call(:get_exposed_host, from, %__MODULE__{host: nil} = state) do
    {:noreply, %{state | waiting: [from | state.waiting]}}
  end

  def handle_call(:get_exposed_host, _from, %__MODULE__{host: host} = state) do
    {:reply, host, state}
  end

  @doc false
  @impl GenServer
  def terminate(reason, %__MODULE__{conn_ref: conn_ref, channel_id: channel_id}) do
    Logger.info("Closing SSH channel and connection due to: #{inspect(reason)}")

    if channel_id do
      :ok = :ssh_connection.close(conn_ref, channel_id)
    end

    :ok = :ssh.close(conn_ref)
    :ok
  end

  @doc """
  Returns the exposed host for the tunnel.
  This function blocks until the tunnel is established and the host is available.
  """
  @spec get_exposed_host(name :: GenServer.name()) :: {:ok, String.t()}
  def get_exposed_host(name \\ @default_name) do
    GenServer.call(name, :get_exposed_host, to_timeout(second: 30))
  end

  @spec default_opts(opts :: Keyword.t()) :: {:ok, {map(), Keyword.t()}} | {:error, term()}
  defp default_opts(opts) do
    with {:ok, opts} <- validate_opts_keys(opts),
         :ok <- validate_required_opts(opts) do
      opts = Map.update!(opts, :ssh_options, &set_default_ssh_options/1)

      {init_opts, start_opts} =
        Map.split(opts, [:ssh_host, :ssh_port, :external_host, :ssh_options, :connect_timeout, :internal_port])

      {:ok, {init_opts, Enum.to_list(start_opts)}}
    end
  end

  @defaults [
    {:name, @default_name},
    {:ssh_host, @default_ssh_host},
    {:ssh_port, @default_ssh_port},
    {:external_host, @default_external_host},
    {:ssh_options, []},
    {:connect_timeout, @default_connect_timeout},
    :internal_port
  ]

  @spec validate_opts_keys(opts :: Keyword.t()) :: {:ok, map()} | {:error, term()}
  defp validate_opts_keys(opts) do
    opts
    |> Keyword.validate(@defaults)
    |> case do
      {:ok, opts} -> {:ok, Map.new(opts)}
      {:error, unknown_options} -> {:error, {:unknown_option, unknown_options}}
    end
  end

  @spec validate_required_opts(opts :: map()) :: :ok | {:error, term()}
  defp validate_required_opts(opts) do
    [:internal_port, :name, :ssh_host, :ssh_port, :ssh_options, :connect_timeout]
    |> Enum.reject(&Map.has_key?(opts, &1))
    |> case do
      [] -> :ok
      missing_keys -> {:error, {:missing_required_option, missing_keys}}
    end
  end

  @spec set_default_ssh_options(opts :: :ssh.client_options()) :: :ssh.client_options()
  defp set_default_ssh_options(opts) do
    opts
    |> Keyword.put_new(:silently_accept_hosts, true)
    |> Keyword.put_new(:user, ~c"nokey")
    |> Keyword.put_new(:quiet_mode, true)
    |> Keyword.put_new(:ip, :any)
  end

  @doc """
  Connects to the SSH server and sets up the tunnel.
  """
  @spec connect(opts :: opts()) :: {:ok, {:ssh.connection_ref(), :ssh.channel_id()}} | {:error, term()}
  def connect(opts) do
    with {:ok, {opts, _start}} <- default_opts(opts) do
      _connect(opts)
    end
  end

  @spec _connect(opts :: internal_opts()) :: {:ok, {:ssh.connection_ref(), :ssh.channel_id()}} | {:error, term()}
  defp _connect(opts) do
    ssh_host = String.to_charlist(opts.ssh_host)
    external_host = String.to_charlist(opts.external_host)

    with {:ok, conn_ref} <- :ssh.connect(ssh_host, opts.ssh_port, opts.ssh_options, opts.connect_timeout),
         {:ok, _internal_port} <-
           :ssh.tcpip_tunnel_from_server(
             conn_ref,
             external_host,
             80,
             ~c"127.0.0.1",
             opts.internal_port,
             opts.connect_timeout
           ),
         {:ok, channel_id} <- :ssh_connection.session_channel(conn_ref, opts.connect_timeout),
         :success <- :ssh_connection.exec(conn_ref, channel_id, ~c"--output json", opts.connect_timeout) do
      {:ok, {conn_ref, channel_id}}
    end
  end
end
