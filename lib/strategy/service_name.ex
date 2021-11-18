defmodule ClusterECS.Strategy.ServiceName do
  @moduledoc """
  This clustering strategy works by loading all containers that have the given
  ECS service as their parent.

  All instances must be started with the same app name and have security groups
  configured to allow inter-node communication.

      config :libcluster,
        topologies: [
          tags_example: [
            strategy: #{__MODULE__},
            config: [
              ecs_clustername: "mycluster",
              ecs_servicename: "myservice",
              app_prefix: "app",
              metadata_to_nodename: &my_nodename_func/2,
              polling_interval: 10_000]]],
              show_debug: false

  ## Configuration Options

  | Key | Required | Description |
  | --- | -------- | ----------- |
  | `:ecs_clustername` | yes | Name of the ECS cluster to search within. |
  | `:ecs_servicename` | yes | Name of the ECS service to look for. |
  | `:app_prefix` | no | Will be prepended to the node's discovered DNS name to create the node name. |
  | `:ip_type` | no | One of :private or :public, defaults to :private |
  | `:metadata_to_nodename` | no | defaults to `app_prefix@node_dns_name` but can be used to override the nodename |
  | `:polling_interval` | no | Number of milliseconds to wait between polls to the ECS api. Defaults to 5_000 |
  | `:show_debug` | no | True or false, whether or not to show the debug log. Defaults to true |
  """

  use GenServer
  use Cluster.Strategy
  import Cluster.Logger
  import SweetXml, only: [sigil_x: 2]

  alias Cluster.Strategy.State

  @default_polling_interval 5_000

  def start_link(opts) do
    Application.ensure_all_started(:tesla)
    Application.ensure_all_started(:ex_aws)
    GenServer.start_link(__MODULE__, opts)
  end

  # libcluster ~> 3.0
  @impl GenServer
  def init([%State{} = state]) do
    state = state |> Map.put(:meta, MapSet.new())

    {:ok, load(state)}
  end

  # libcluster ~> 2.0
  def init(opts) do
    state = %State{
      topology: Keyword.fetch!(opts, :topology),
      connect: Keyword.fetch!(opts, :connect),
      disconnect: Keyword.fetch!(opts, :disconnect),
      list_nodes: Keyword.fetch!(opts, :list_nodes),
      config: Keyword.fetch!(opts, :config),
      meta: MapSet.new([])
    }

    {:ok, load(state)}
  end

  @impl GenServer
  def handle_info(:timeout, state) do
    handle_info(:load, state)
  end

  def handle_info(:load, %State{} = state) do
    {:noreply, load(state)}
  end

  def handle_info(_, state) do
    {:noreply, state}
  end

  defp load(%State{topology: topology, connect: connect, disconnect: disconnect, list_nodes: list_nodes} = state) do
    case get_nodes(state) do
      {:ok, new_nodelist} ->
        added = MapSet.difference(new_nodelist, state.meta)
        removed = MapSet.difference(state.meta, new_nodelist)
        new_nodelist = topology
          |> Cluster.Strategy.disconnect_nodes(disconnect, list_nodes, MapSet.to_list(removed))
          |> case() do
            :ok ->
              new_nodelist
            {:error, bad_nodes} ->
              # Add back the nodes which should have been removed, but which couldn't be for some reason
              Enum.reduce(bad_nodes, new_nodelist, fn {n, _}, acc ->
                MapSet.put(acc, n)
              end)
          end
        new_nodelist = topology
          |> Cluster.Strategy.connect_nodes(connect, list_nodes, MapSet.to_list(added))
          |> case() do
            :ok ->
              new_nodelist
            {:error, bad_nodes} ->
              # Remove the nodes which should have been added, but couldn't be for some reason
              Enum.reduce(bad_nodes, new_nodelist, fn {n, _}, acc ->
                MapSet.delete(acc, n)
              end)
          end
        Process.send_after(self(), :load, Keyword.get(state.config, :polling_interval, @default_polling_interval))
        # retval this case branch
        %{state | :meta => new_nodelist}
      _ ->
        Process.send_after(self(), :load, Keyword.get(state.config, :polling_interval, @default_polling_interval))
        state
    end
  end

  @spec get_nodes(State.t()) :: {:ok, [atom()]} | {:error, []}
  defp get_nodes(%State{topology: topology, config: config}) do
    instance_id = ClusterECS.local_instance_arn()
    region = ClusterECS.instance_region()

    cluster_name = Keyword.fetch!(config, :ecs_clustername)
    service_name = Keyword.fetch!(config, :ecs_servicename)
    app_prefix = Keyword.get(config, :app_prefix, "app")
    metadata_to_nodename = Keyword.get(config, :metadata_to_nodename, &metadata_to_nodename/2)
    show_debug? = Keyword.get(config, :show_debug, true)

    cond do
      app_prefix != nil and instance_id != "" and region != "" ->
        with {:ok, cluster_arn} <- get_cluster_arn_by_name(cluster_name),
          {:ok, service_arn} <- get_service_arn_by_name(cluster_arn, service_name),
          {:ok, task_arns} <- get_task_arns_by_service(cluster_arn, service_arn),
          {:ok, container_meta} <- describe_tasks_by_arn(cluster_arn, task_arns)
        do
          resp = container_meta
            |> map_ecs_enis_to_containers()
            |> metadata_to_nodename.(app_prefix)
            |> MapSet.new()
          {:ok, resp}
        else
          _ ->
            {:error, []}
        end

      instance_id == "" ->
        warn(topology, "instance id could not be fetched!")
        {:error, []}

      region == "" ->
        warn(topology, "region could not be fetched!")
        {:error, []}

      :else ->
        warn(topology, "ecs service-name strategy is selected, but is not configured!")
        {:error, []}
    end
  end

  # only public for testing
  @doc false
  def get_cluster_arn_by_name(target_cluster_name, exaws_options \\ []) do
    exaws_opspec = ExAws.ECS.list_clusters()
    filter_callback = fn elm ->
        [_, cluster_name] = String.split(elm, "/", parts: 2)
        cluster_name === target_cluster_name
      end
    with {:ok, %{"clusterArns" => [_|_] = arn_list}} <- ExAws.request(exaws_opspec, exaws_options),
      ret when is_binary(ret) <- Enum.find(arn_list, filter_callback)
    do {:ok, ret}
    else
      {:error, _} = errtuple -> errtuple
      nil -> {:error, :not_found}
    end
  end

  @doc false
  def get_service_arn_by_name(cluster_arn, target_service_name, exaws_options \\ []) do
    exaws_opspec = ExAws.ECS.list_services([cluster: cluster_arn])
    filter_callback = fn elm ->
        [_, service_name] = String.split(elm, "/", parts: 2)
        service_name === target_service_name
      end
    with {:ok, %{"serviceArns" => [_|_] = arn_list}} <- ExAws.request(exaws_opspec, exaws_options),
      ret when is_binary(ret) <- Enum.find(arn_list, filter_callback)
    do {:ok, ret}
    else
      {:error, _} = errtuple -> errtuple
      nil -> {:error, :not_found}
    end
  end

  @doc false
  def get_task_arns_by_service(cluster_arn, service_arn, exaws_options \\ []) do
    exaws_opspec = ExAws.ECS.list_tasks(cluster_arn, [service: service_arn])
    with {:ok, %{"taskArns" => [_|_] = arn_list}} <- ExAws.request(exaws_opspec, exaws_options) do
      {:ok, arn_list}
    end
  end

  @doc false
  def describe_tasks_by_arn(cluster_arn, task_arns, exaws_options \\ []) when is_list(task_arns) do
    cluster_arn
    |> ExAws.ECS.describe_tasks(task_arns)
    |> ExAws.request(exaws_options)
  end

  @doc false
  def map_ecs_enis_to_containers(%{"tasks" => container_meta}) do
    container_meta
    |> Enum.map(fn %{"attachments" => netifs, "containers" => containers} = ecs_task ->
        # transform the attachments list into an ID=>info map
        netifs_by_uuid = Map.new(netifs, fn %{"id" => k, "details" => detail_list} = netif ->
            {k, %{netif | "details" => 
              # transform the "details" list-of-maps into an `inner_map["name"]=>inner_map["value"]`-pairs map
              Map.new(detail_list, fn %{"name" => ik, "value" => v} -> {ik, v} end)}}
          end)
        Enum.map(containers, fn %{"networkInterfaces" => iface_list} = container ->
            %{container | "networkInterfaces" =>
              Enum.map(iface_list, fn %{"attachmentId" => eni_key} -> Map.fetch!(netifs_by_uuid, eni_key) end)}
          end)
      end)
    |> List.flatten()
    |> Map.new(fn %{"containerArn" => k, "networkInterfaces" => nifinfo} = val2 ->
        val1 = Enum.map(nifinfo, fn %{"details" => %{"privateDnsName" => v}} -> v end)
        # key = container ARN, value = {list of privateDnsName, entire container metadata}
        # this is done instead of just ARN=>privateDnsName for user-supplied `metadata_to_nodename/2`,
        # in case the user needs access to other metadata
        {k, {val1, val2}}
      end)
  end

  defp metadata_to_nodename(metadata_map, app_prefix) when is_map(metadata_map) do
    metadata_map
    |> Enum.map(fn {_k, {val1, _}} -> val1 end)
    |> List.flatten()
    |> Enum.map(fn elm -> app_prefix <> "@" <> elm end)
  end

  # kept around for reference, not used.
  defp ip_to_nodename(list, app_prefix) when is_list(list) do
    list
    |> Enum.map(fn ip ->
      :"#{app_prefix}@#{ip}"
    end)
  end
end
