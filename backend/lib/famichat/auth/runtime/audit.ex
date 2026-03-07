defmodule Famichat.Auth.Runtime.Audit do
  @moduledoc """
  Persists authentication audit events to `auth_audit_logs`.
  """

  alias Ecto.Changeset
  alias Famichat.Auth.Runtime.AuditLog
  alias Famichat.Repo

  @typedoc "Accepted attributes for audit rows."
  @type attrs ::
          %{
            optional(:actor_id) => Ecto.UUID.t(),
            optional(:subject_id) => Ecto.UUID.t(),
            optional(:community_id) => Ecto.UUID.t(),
            optional(:household_id) => Ecto.UUID.t(),
            required(:scope) => atom() | String.t(),
            optional(:metadata) => map()
          }

  @doc """
  Records a single audit entry. Returns `:ok` or `{:error, changeset}`.
  """
  @spec record(String.t(), attrs()) :: :ok | {:error, Changeset.t()}
  def record(event, attrs) when is_binary(event) and is_map(attrs) do
    attrs
    |> normalize_attrs(event)
    |> do_insert()
  end

  def record(event, attrs) when is_binary(event) and is_list(attrs),
    do: record(event, Map.new(attrs))

  @doc """
  Records multiple audit entries for the same event.
  Halts on the first error and returns `{:error, changeset}`.
  """
  @spec record_many(String.t(), [attrs()]) :: :ok | {:error, Changeset.t()}
  def record_many(event, entries) when is_binary(event) and is_list(entries) do
    Enum.reduce_while(entries, :ok, fn entry, :ok ->
      case record(event, entry) do
        :ok -> {:cont, :ok}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
  end

  defp do_insert(attrs) do
    %AuditLog{}
    |> AuditLog.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, _log} -> :ok
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp normalize_attrs(attrs, event) do
    attrs
    |> Map.put(:event, event)
    |> Map.update(:scope, "target_user", &normalize_scope/1)
    |> Map.update(:metadata, %{}, &ensure_map/1)
  end

  defp normalize_scope(scope) when is_atom(scope), do: Atom.to_string(scope)
  defp normalize_scope(scope) when is_binary(scope), do: scope

  defp ensure_map(value) when is_map(value), do: value
  defp ensure_map(_), do: %{}
end
