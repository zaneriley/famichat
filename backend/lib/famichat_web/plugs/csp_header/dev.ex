defmodule FamichatWeb.Plugs.CSPHeader.Dev do
  @moduledoc """
  Development environment specific CSP functions.
  """

  @spec script_src(String.t()) :: String.t()
  def script_src(all_hosts),
    do: "'self' #{all_hosts} 'unsafe-inline' 'unsafe-eval'"

  @spec frame_src() :: String.t()
  def frame_src, do: "'self'"

  @spec maybe_add_upgrade_insecure_requests(keyword()) :: keyword()
  def maybe_add_upgrade_insecure_requests(directives), do: directives
end
