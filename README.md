ClusterECS
==========

This is a collection of ECS clustering strategies for  [libcluster](https://hexdocs.pm/libcluster/). It currently supports identifying nodes based on an EC2 cluster name + service name.

```
config :libcluster,
  topologies: [
    example: [
      strategy: ClusterECS.Strategy.ServiceName,
      config: [
      	ecs_clustername: "my-ec2-cluster",
	ecs_servicename: "my-ecs-service"
      ],
    ]
  ]
```

## Installation

The package can be installed
by adding `libcluster_ecs` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [{:libcluster_ecs, github: "Genyes/libcluster_ecs"}]
end
```

## Acknowledgements
This package is directly based on [libcluster\_ec2](https://github.com/kyleaa/libcluster_ec2).
