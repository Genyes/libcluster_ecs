defmodule ClusterECS.Mixfile do
  use Mix.Project
  @git_repo "https://github.com/Genyes/libcluster_ecs"

  def project do
    [
      app: :libcluster_ecs,
      version: "0.6.0",
      elixir: "~> 1.4",
      name: "libcluster_ecs",
      source_url: @git_repo,
      homepage_url: @git_repo,
      description: description(),
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package()
    ]
  end

  # Configuration for the OTP application
  #
  # Type "mix help compile.app" for more information
  def application do
    # Specify extra applications you'll use from Erlang/Elixir
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:libcluster, "~> 2.0 or ~> 3.0"},
      {:ex_aws, "~> 2.0"},
      {:ex_aws_ecs, "~> 0.1.2"},
      {:sweet_xml, "~> 0.6"},
      {:hackney, "~> 1.8"},
      {:poison, ">= 1.0.0"},
      {:tesla, "~> 1.0"},
      {:ex_doc, ">= 0.0.0", only: :dev}
    ]
  end

  defp description do
    """
    ECS clustering strategy for libcluster
    """
  end

  def package do
    [
      maintainers: ["Youth and Educators Succeeding"],
      licenses: ["MIT License"],
      links: %{
        "GitHub" => "#{@git_repo}.git"
      }
    ]
  end
end
