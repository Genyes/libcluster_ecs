# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
use Mix.Config

# This configuration is loaded before any dependency and is restricted
# to this project. If another project depends on this project, this
# file won't be loaded nor affect the parent project. For this reason,
# if you want to provide default values for your application for
# 3rd-party users, it should be done in your "mix.exs" file.

# You can configure for your application as:
#
#     config :libcluster_ec2, key: :value
#
# And access this configuration in your application as:
#
#     Application.get_env(:libcluster_ec2, :key)
#
# Or configure a 3rd-party app:
#
#     config :logger, level: :info
#

# It is also possible to import configuration files, relative to this
# directory. For example, you can emulate configuration per environment
# by uncommenting the line below and defining dev.exs, test.exs and such.
# Configuration from the imported file will override the ones defined
# here (which is why it is important to import them last).
#
#     import_config "#{Mix.env}.exs"

# default value, override in your build-time or run-time config as desired.
config :libcluster_ecs, :json_parser, Jason

# default value; you *will* need to override this in your run-time config!
config :libcluster_ecs, :api_endpoint, System.get_env("ECS_CONTAINER_METADATA_URI_V4")

if Mix.env() == :test do
  config :ex_aws,
    access_key_id: "xxx",
    secret_access_key: "xxx"

  config :tesla, adapter: Tesla.Mock

  config :libcluster_ecs, :api_endpoint, "https://169.254.169.254"
end
