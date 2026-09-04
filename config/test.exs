import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :estimate, env: :test

config :estimate, Estimate.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  port: 5499,
  database: "estimate_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2,
  after_connect: {Estimate.Repo, :after_connect, []}

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :estimate, EstimateWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "WyahsRvtDfbgQIdrb/QfgxldOOK3/iIOXMuloQ04SPWv+HYEVCfS+6rNRlkOOixL",
  server: false

# In test we don't send emails
config :estimate, Estimate.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# All tests share 127.0.0.1; only per-identity buckets are meaningful here.
config :estimate, Estimate.RateLimit, login_ip: 100_000, oauth_ip: 100_000

# Disabled so the supervised janitor never runs on its own timer during
# tests; test/estimate/mcp/oauth_janitor_test.exs calls Janitor.run() directly.
config :estimate, Estimate.MCP.OAuth.Janitor, enabled: false

# 1 hop so tests that set a single x-forwarded-for value keep working.
config :estimate, EstimateWeb.ClientIP, trusted_proxy_hops: 1

# No ENCRYPTION_KEY by default; the ring has only the SECRET_KEY_BASE-derived v1.
config :estimate, Estimate.Encryption, key: nil
