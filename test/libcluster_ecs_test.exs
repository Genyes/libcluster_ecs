defmodule ClusterECSTest do
  use ExUnit.Case
  doctest ClusterECS

  @json_parser Application.fetch_env!(:libcluster_ecs, :json_parser)
  setup do
    Tesla.Mock.mock(fn
      %{method: :get, url: "https://169.254.169.254/"} ->
        %Tesla.Env{status: 200, body: @json_parser.encode!(%{"ContainerARN" => "arn:invalid"})}

      %{method: :get, url: "https://169.254.169.254/task"} ->
        %Tesla.Env{status: 200, body: @json_parser.encode!(%{"AvailabilityZone" => "us-east-2b"})}
    end)

    :ok
  end

  test "return local_instance_arn" do
    assert "arn:invalid" == ClusterECS.local_instance_arn()
  end

  test "return instance_region" do
    assert "us-east-2" == ClusterECS.instance_region()
  end
end
