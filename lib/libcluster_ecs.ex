defmodule ClusterECS do
  use Tesla
  @moduledoc ~s"""
  Required config entries:
  ```
  config :libcluster_ecs, :api_base_uri, binary()
  config :libcluster_ecs, :json_parser, module()
  ```

  Valid parameter values:
  * `:json_parser`: The module name of any JSON parser conforming to the same API as `Jason` and `Poison`.
    In particular, it must implement the following methods:
    * `decode!/1`
  * `:api_base_uri`: The base URI for the ECS Container Metadata API v4 endpoint.
    Usually accessible via `System.get_env("ECS_CONTAINER_METADATA_URI_V4")` at runtime.
  """

  defp json_parser do
    Application.fetch_env!(:libcluster_ecs, :json_parser)
  end

  defp resolve_tesla_base() do
    case Application.get_env(:libcluster_ecs, :api_base_uri) do
      nil ->
        require Logger
        Logger.error(fn-> "App env dump: #{Application.get_all_env(:libcluster_ecs) |> inspect(limit: :infinity)}" end)
        Logger.flush()
        raise ExAws.Error, "ECS Container Metadata API v4: endpoint URI not found. See docs for `ClusterECS` in the `:libcluster_ecs` application.."
      thing when is_binary(thing) -> thing
    end
  end

  plug(Tesla.Middleware.BaseUrl, resolve_tesla_base())

  @doc """
  Queries the local ECS instance metadata V4 API to determine the instance ARN of the current container.
  If the base path 404s, fall back to extracting the current container's metadata from the task's metadata.
  """
  @spec local_instance_arn() :: binary()
  def local_instance_arn do
    with {:ok, %{status: 200, body: _body}} <- get("/"),
      {:ok, %{"ContainerARN" => result}} <- json_parser().decode()
    do
      result
    else
      {:ok, %{status: 404}} -> local_instance_arn_404workaround()
      {:ok, bogus_result} -> {:error, bogus_result}
    end
  end

  # Sometimes the V4 API endpoint returns 404 for the container metadata, for reasons unknown.
  # If that happens, get the task metadata, find the container by its DNS name, and extract the ARN from there.
  defp local_instance_arn_404workaround do
    with {:ok, %{status: 200, body: body_text}} <- Tesla.get("/task"),
      {:ok, %{"Containers" => container_list}} <- json_parser().decode(body_text)
    do
      [_, my_dns_name] = node()
        |> Atom.to_string()
        |> String.split("@", parts: 2)

      container_list
      |> Enum.find(fn %{"Networks" => nets} ->
          Enum.any?(nets, fn
            %{"PrivateDNSName" => ^my_dns_name} -> true
            _ -> false
          end)
        end)
      |> Map.fetch!("ContainerARN")
    end
  end

  @doc """
  Queries the local ECS instance metadata API to determine the aws resource region of the current container's task.
  """
  @spec instance_region() :: binary()
  def instance_region do
    case get("/task") do
      {:ok, %{status: 200, body: body}} ->
        body
        |> json_parser().decode!()
        |> Map.fetch!("AvailabilityZone")
        |> String.slice(0..-2)
    end
  end
end
