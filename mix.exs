defmodule ProcessTreeDictionary.Mixfile do
  use Mix.Project

  def project do
    [app: :process_tree_dictionary,
     version: "0.1.0",
     elixir: "~> 1.3",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps()]
  end

  def application do
    [applications: [:logger]]
  end

  defp deps do
    [
      # ex_doc and earmark are necessary to publish docs to hexdocs.pm.
      {:ex_doc, ">= 0.0.0", only: :dev},
      {:earmark, ">= 0.0.0", only: :dev},
    ]
  end
end
