defmodule LocalhostRun.MixProject do
  use Mix.Project

  def project do
    [
      app: :localhost_run,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      name: "localhost.run",
      source_url: "https://github.com/erlef/localhost-run",
      docs: &docs/0,
      description: "Expose local ports to the internet via SSH tunnels using Elixir and localhost.run.",
      package: package(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.github": :test,
        "coveralls.multiple": :test
      ]
    ]
  end

  defp package do
    [
      maintainers: ["Jonatan Männchen"],
      files: [
        "lib",
        "LICENSE*",
        "mix.exs",
        "README*"
      ],
      licenses: ["Apache-2.0"],
      links: %{"Github" => "https://github.com/erlef/localhost-run"}
    ]
  end

  defp docs do
    {ref, 0} = System.cmd("git", ["rev-parse", "--verify", "--quiet", "HEAD"])

    [
      main: "readme",
      source_ref: ref,
      extras: ["README.md"]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :ssh]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp deps do
    # styler:sort
    [
      {:bandit, "~> 1.6", only: [:dev, :test]},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.37.3", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18.5", only: :test, runtime: false},
      {:plug, "~> 1.17", only: [:dev, :test]},
      {:req, "~> 0.5.10", only: [:dev, :test]},
      {:styler, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end
end
