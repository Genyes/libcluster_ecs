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

  @json_parser Application.get_env(:libcluster_ecs, :json_parser, {:error, :not_found})

  defp resolve_tesla_base() do
    case Application.get_env(:libcluster_ecs, :api_base_uri) do
      nil -> raise ExAws.Error, "ECS Container Metadata API v4: endpoint URI not found. See docs for `ClusterECS` in the `:libcluster_ecs` application.."
      thing when is_binary(thing) -> thing
    end
  end

  plug(Tesla.Middleware.BaseUrl, resolve_tesla_base())

  @doc """
  Queries the local ECS instance metadata API to determine the instance ARN of the current container.
  """
  @spec local_instance_arn() :: binary()
  def local_instance_arn do
    case get("/") do
      {:ok, %{status: 200, body: body}} ->
        body
        |> @json_parser.decode!()
        |> Map.get!("ContainerARN")
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
        |> @json_parser.decode!()
        |> Map.get!("AvailabilityZone")
        |> String.slice(0..-2)
    end
  end
end
