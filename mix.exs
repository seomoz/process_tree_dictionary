defmodule ProcessTreeDictionary.Mixfile do
  use Mix.Project

  def project do
    [app: :process_tree_dictionary,
     version: "1.0.2",
     elixir: "~> 1.3",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     aliases: aliases,
     description: description,
     package: package,
     deps: deps()]
  end

  def application do
    [applications: []]
  end

  defp deps do
    [
      # ex_doc and earmark are necessary to publish docs to hexdocs.pm.
      {:ex_doc, ">= 0.0.0", only: :dev},
      {:earmark, ">= 0.0.0", only: :dev},
    ]
  end

  defp description do
    """
    Implements a dictionary that is scoped to a process tree for Erlang and Elixir.
    """
  end

  defp package do
    [
      licenses: ["MIT"],
      maintainers: ["Myron Marston"],
      links: %{"GitHub" => "https://github.com/seomoz/process_tree_dictionary"},
    ]
  end

  defp aliases do
    [
      "hex.publish": ["hex.publish", &tag_version/1],
    ]
  end

  defp tag_version(_args) do
    version = Keyword.fetch!(project, :version)
    System.cmd("git", ["tag", "-a", "-m", "Version #{version}", "v#{version}"])
    System.cmd("git", ["push", "origin"])
    System.cmd("git", ["push", "origin", "--tags"])
  end
end
