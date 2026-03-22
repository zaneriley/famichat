defmodule Famichat.MixProject do
  use Mix.Project

  def project do
    [
      app: :famichat,
      version: "0.0.1",
      elixir: "~> 1.13",
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: compilers(Mix.env()),
      start_permanent: Mix.env() == :prod,
      build_path:
        if(System.get_env("DOCKER_BUILD"), do: "/mix/_build", else: "_build"),
      deps_path:
        if(System.get_env("DOCKER_BUILD"), do: "/mix/deps", else: "deps"),
      aliases: aliases(),
      deps: deps(),
      dialyzer: [
        plt_add_apps: [:ex_unit, :mix],
        ignore_warnings: ".dialyzer_ignore.exs",
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"}
      ],

      # Documentation
      name: "Famichat",
      source_url: "https://github.com/your-user/famichat",
      homepage_url: "https://github.com/your-user/famichat",
      docs: docs()
    ]
  end

  def application do
    [
      mod: {Famichat.Application, []},
      extra_applications: [:logger, :runtime_tools, :cloak]
    ]
  end

  defp compilers(:test), do: Mix.compilers()
  defp compilers(_), do: [:boundary] ++ Mix.compilers()

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:bcrypt_elixir, "~> 3.0"},
      {:cachex, "~> 3.6"},
      {:cowboy, "~> 2.11.0"},
      {:credo, "~> 1.7.11", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:dns_cluster, "~> 0.1.3"},
      {:earmark, "~> 1.4"},
      {:ecto_sql, "3.11.3"},
      {:ex_doc, "~> 0.37.3", only: :dev, runtime: false},
      {:ex_machina, "~> 2.7.0", only: :test},
      {:finch, "0.18.0"},
      {:file_system, "~> 1.0.0"},
      {:floki, "~> 0.36.2", only: :test},
      {:gettext, "0.24.0"},
      {:heroicons, "0.5.5"},
      {:jason, "~> 1.2"},
      {:logfmt_ex, "~> 0.4.2"},
      {:mox, "~> 1.2.0", only: :test},
      {:stream_data, "~> 0.6", only: :test},
      {:phoenix, "1.7.14"},
      {:phoenix_ecto, "4.6.2"},
      {:phoenix_html, "4.1.1"},
      {:phoenix_live_dashboard, "0.8.4"},
      {:phoenix_live_reload, "1.5.3", only: :dev},
      {:phoenix_live_view, "0.20.17"},
      {:plug_cowboy, "~> 2.1"},
      {:postgrex, "0.18.0"},
      {:sobelow, "~> 0.13", only: [:dev, :test], runtime: false},
      {:swoosh, "1.16.9"},
      {:telemetry_metrics, "1.0.0"},
      {:telemetry_poller, "1.1.0"},
      {:timex, "~> 3.7"},
      {:yamerl, "~> 0.10.0"},
      {:uuid, "~> 1.1"},
      {:telemetry_test, "~> 0.1.0", only: :test},
      {:cloak_ecto, "~> 1.3"},
      {:wax_, "~> 0.6"},
      {:rustler, "~> 0.37"},
      {:boundary, "~> 0.9", runtime: false}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "cmd npm install --prefix assets"],
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      "ecto.setup_with_seed": ["ecto.setup", "ecto.seed"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "ecto.seed": ["run priv/repo/seeds.exs"]
    ]
  end

  defp docs do
    [
      # The main page in the docs
      main: "overview",
      extras: [
        "guides/overview.md": [title: "Project Overview"],
        "guides/messaging.md": [title: "Messaging Implementation"],
        "guides/telemetry.md": [title: "Telemetry & Performance"]
      ],
      groups_for_extras: [
        Guides: ~r/guides\/.*/
      ],
      groups_for_modules: [
        Chat: [
          Famichat.Chat,
          ~r/Famichat\.Chat\..*/
        ],
        Accounts: [
          Famichat.Accounts,
          ~r/Famichat\.Accounts\..*/
        ],
        Web: [
          FamichatWeb,
          ~r/FamichatWeb\..*/
        ]
      ]
    ]
  end
end
