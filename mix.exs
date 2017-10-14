defmodule Nodex.Mixfile do
  use Mix.Project

  def project do
    [
      app: :nodex,
      version: "0.1.1",
      elixir: "~> 1.5",
      # When writing a package that depends on extra build steps
      # include your custom mix compile task here:
      # compilers: [:nodex_make, :elixir, :app],
      description: "Nodex provides helping functionality around distributed Elixir.",
      package: package(),
      start_permanent: Mix.env == :prod,
      deps: deps()
    ]
  end

  def package do
    [
      maintainers: ["Lukas Rieder"],
      licenses: ["GNU LGPL"],
      links: %{
        "Github" => "https://github.com/Overbryd/nodex",
        "Issues" => "https://github.com/Overbryd/nodex/issues"
      },
      files: [
        "lib",
        "test",
        "mix.exs",
        "README.md",
        "LICENSE"
        # When packaging a project that needs to compile extra stuff
        # make sure you include these files and the priv/ directory
        # in the hex package.
        #
        # "c_src",
        # "priv/.gitignore",
        # "Makefile",
        # "Makefile.Darwin",
        # "Makefile.Linux"
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # documentation helpers
      {:ex_doc, ">= 0.0.0", only: :dev},
      # benchmarking helpers
      {:benchfella, "~> 0.3.0", only: :dev}
    ]
  end
end

defmodule Mix.Tasks.Compile.NodexMake do
  @artifacts [
    "priv/example_client",
    "priv/just_exit"
  ]

  def run(_) do
    if match? {:win32, _}, :os.type do
      IO.warn "Windows is not yet a target."
      exit(1)
    else
      {result, _error_code} = System.cmd("make",
        @artifacts,
        stderr_to_stdout: true,
        env: [{"MIX_ENV", to_string(Mix.env)}]
      )
      IO.binwrite result
    end
    :ok
  end

  def clean() do
    {result, _error_code} = System.cmd("make", ["clean"], stderr_to_stdout: true)
    Mix.shell.info result
    :ok
  end
end

