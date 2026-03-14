defmodule FamichatWeb.AppName do
  @moduledoc false

  def app_name do
    Application.get_env(:famichat, :app_name, "Famichat")
  end
end
