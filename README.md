# LocalhostRun

[![Main Branch](https://github.com/erlef/localhost-run/actions/workflows/branch_main.yml/badge.svg?branch=main)](https://github.com/erlef/localhost-run/actions/workflows/branch_main.yml)
[![Module Version](https://img.shields.io/hexpm/v/localhost_run.svg)](https://hex.pm/packages/localhost_run)
[![Total Download](https://img.shields.io/hexpm/dt/localhost_run.svg)](https://hex.pm/packages/localhost_run)
[![License](https://img.shields.io/hexpm/l/localhost_run.svg)](https://github.com/erlef/localhost-run/blob/main/LICENSE)
[![Last Updated](https://img.shields.io/github/last-commit/erlef/localhost-run.svg)](https://github.com/erlef/localhost-run/commits/master)
[![Coverage Status](https://coveralls.io/repos/github/erlef/localhost-run/badge.svg?branch=main)](https://coveralls.io/github/erlef/localhost-run?branch=main)

A small Elixir client for [localhost.run](https://localhost.run), which lets you
expose local ports to the internet via SSH tunnels.

This can be useful for development, testing webhooks, or sharing a local server
with someone. It supports both unauthenticated and authenticated connections
using SSH keys or your local SSH agent.

## Installation

Add to your `mix.exs`:

```elixir
def deps do
  [
    {:localhost_run, "~> 0.1.0"}
  ]
end
```

## Basic Usage

You can use this module in different ways depending on your needs.

### Start with `GenServer`

```elixir
{:ok, pid} = LocalhostRun.start_link(internal_port: 4000)
```

### As a supervised process

```elixir
children = [
  {LocalhostRun, [internal_port: 4000]}
]

opts = [strategy: :one_for_one, name: MyApp.Supervisor]
Supervisor.start_link(children, opts)
```

### Manual connection

```elixir
{:ok, {conn_ref, channel_id}} = LocalhostRun.connect(internal_port: 4000)

receive do
  {:ssh_cm, ^conn_ref, {:data, ^channel_id, 0, message}} ->
    case JSON.decode!(message) do
      %{"event" => "tcpip-forward", "address" => host} ->
        Logger.info("Tunnel established to #{host}")

      %{"event" => "authn", "message" => msg} ->
        Logger.info("Authentication successful: #{msg}")

      %{"message" => msg} ->
        Logger.debug("Received: #{inspect(msg)}")
    end
end
```

## Authentication

To use features like custom domains or longer tunnel timeouts, you’ll need to
authenticate with localhost.run.

See their [docs](https://localhost.run/docs/custom-domains) for details.

You have two options:

### SSH agent

Make sure your SSH agent is running and your key is added:

```bash
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_rsa
```

Then pass the agent to `LocalhostRun`:

```elixir
{:ok, pid} = LocalhostRun.start_link(internal_port: 4000, ssh_options: [
  user: "your_username",
  key_cb: {:ssh_agent, []}
])
```

### SSH key file

Alternatively, you can specify a key file:

```elixir
{:ok, pid} = LocalhostRun.start_link(internal_port: 4000, ssh_options: [
  user: "your_username",
  key_cb: {:ssh_file, []}
])
```

## Getting the tunnel address

If you need to get the public address of the tunnel:

```elixir
{:ok, host} = LocalhostRun.get_exposed_host()
IO.puts("Tunnel is available at #{host}")
```

## Logging

The module sets some helpful metadata in your logs:

* `:ssh_host`
* `:ssh_port`
* `:external_host`
* `:internal_port`

This can help with debugging or tracing tunnel usage.

## License

    Copyright 2025 Jonatan Männchen
    Copyright 2025 Erlang Ecosystem Foundation

    Licensed under the Apache License, Version 2.0 (the "License");
    you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

        http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and
    limitations under the License.
