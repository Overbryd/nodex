defmodule Cnodex.Mixfile do
  use Mix.Project

  def project do
    [
      app: :cnodex,
      version: "0.1.0",
      elixir: "~> 1.5",
      # You can prepend make to your compilers if you like
      # That way running `mix compile` will also compile your C-artifacts.
      #
      # compilers: [:make, :elixir, :app],
      start_permanent: Mix.env == :prod,
      deps: deps()
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

defmodule Mix.Tasks.Compile.CnodexMake do
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

