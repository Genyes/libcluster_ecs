defmodule Strategy.ServiceNameTest do
  use ExUnit.Case, async: false
  #doctest ClusterECS

  @json_codec Application.fetch_env!(:libcluster_ecs, :json_parser)
  @cluster_config [ecs_clustername: "libcluster-ecs-test-cluster",
    ecs_servicename: "libcluster-ecs-test-service"]

  setup do
    Tesla.Mock.mock_global(fn
      %{method: :get, url: "https://169.254.169.254/"} ->
        %Tesla.Env{status: 200, body: @json_codec.encode!(%{
          "ContainerARN" => "arn:test:CurrentContainer"
        })}

      %{method: :get, url: "https://169.254.169.254/task"} ->
        %Tesla.Env{status: 200, body: @json_codec.encode!(%{"AvailabilityZone" => "us-east-2b"})}
    end)

    ops = [
      topology: ClusterECS.Strategy.ServiceName,
      connect: {:net_kernel, :connect, []},
      disconnect: {:net_kernel, :disconnect, []},
      list_nodes: {:erlang, :nodes, [:connected]},
      config: @cluster_config
    ]

    {:ok, server_pid} = ClusterECS.Strategy.ServiceName.start_link(ops)
    {:ok, server: server_pid}
  end

  test "test info call :load", %{server: pid} do
    assert :load == send(pid, :load)

    assert %Cluster.Strategy.State{
             config: @cluster_config,
             connect: {:net_kernel, :connect, []},
             disconnect: {:net_kernel, :disconnect, []},
             list_nodes: {:erlang, :nodes, [:connected]},
             meta: MapSet.new([]),
             topology: ClusterECS.Strategy.ServiceName
           } == :sys.get_state(pid)
  end
end
