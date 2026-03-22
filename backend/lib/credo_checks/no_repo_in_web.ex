if Code.ensure_loaded?(Credo.Check) do
  defmodule Credo.Check.Custom.NoRepoInWeb do
    use Boundary, top_level?: true, deps: [], exports: []

    use Credo.Check,
      base_priority: :high,
      category: :design,
      explanations: [
        check: """
        Web layer modules (`famichat_web/`) must not call `Famichat.Repo` directly.
        Use a context function in `Famichat.Chat`, `Famichat.Accounts`, or
        `Famichat.Auth.*` instead.

        Exemptions: `UpController` (health check probe).
        """
      ]

    @impl true
    def run(%Credo.SourceFile{} = source_file, params) do
      if web_layer_file?(source_file.filename) and
           not exempted?(source_file.filename) do
        issue_meta = IssueMeta.for(source_file, params)

        Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
      else
        []
      end
    end

    defp web_layer_file?(filename) do
      String.contains?(filename, "famichat_web")
    end

    defp exempted?(filename) do
      String.ends_with?(filename, "up_controller.ex")
    end

    # Match: alias Famichat.Repo
    defp traverse(
           {:alias, meta, [{:__aliases__, _, [:Famichat, :Repo]}]} = ast,
           issues,
           issue_meta
         ) do
      {ast,
       issues ++ [issue_for(issue_meta, meta[:line], "alias Famichat.Repo")]}
    end

    # Match: Famichat.Repo.function_call(...)
    defp traverse(
           {{:., _, [{:__aliases__, meta, [:Famichat, :Repo]}, _fun]}, _, _args} =
             ast,
           issues,
           issue_meta
         ) do
      {ast, issues ++ [issue_for(issue_meta, meta[:line], "Famichat.Repo")]}
    end

    defp traverse(ast, issues, _issue_meta), do: {ast, issues}

    defp issue_for(issue_meta, line_no, trigger) do
      format_issue(
        issue_meta,
        message:
          "Web layer should not use Famichat.Repo directly. Use a context function instead.",
        trigger: trigger,
        line_no: line_no
      )
    end
  end
end
