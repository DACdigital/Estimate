import Config

if config_env() in [:dev, :test] do
  Dotenvy.source!([".env", System.get_env()])
end

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/estimate start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :estimate, EstimateWeb.Endpoint, server: true
end

config :estimate, EstimateWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

if google_client_id = System.get_env("GOOGLE_CLIENT_ID") do
  config :estimate, :google_oauth,
    client_id: google_client_id,
    client_secret: System.get_env("GOOGLE_CLIENT_SECRET")
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :estimate, Estimate.Repo,
    # ssl: true,
    # TODO: enable once prod PG has SSL configured
    # ssl_opts: [verify: :verify_peer, cacerts: :public_key.cacerts_get()],
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "20"),
    queue_target: 5_000,
    queue_interval: 1_000,
    socket_options: maybe_ipv6,
    after_connect: {Estimate.Repo, :after_connect, []}

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host =
    System.get_env("PHX_HOST") ||
      raise "environment variable PHX_HOST is missing."

  config :estimate, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  # How many x-forwarded-for hops to trust (see EstimateWeb.ClientIP moduledoc).
  # Set to 0 when the app is exposed directly, with no reverse proxy in front of it.
  config :estimate, EstimateWeb.ClientIP,
    trusted_proxy_hops: String.to_integer(System.get_env("TRUSTED_PROXY_HOPS", "1"))

  # Rate limits for auth-sensitive endpoints (see Estimate.RateLimit). Defaults match
  # config/config.exs; override per-deployment via env if traffic patterns warrant it.
  config :estimate, Estimate.RateLimit,
    login_email: String.to_integer(System.get_env("RATE_LIMIT_LOGIN_EMAIL", "10")),
    login_ip: String.to_integer(System.get_env("RATE_LIMIT_LOGIN_IP", "60")),
    totp_attempt: String.to_integer(System.get_env("RATE_LIMIT_TOTP_ATTEMPT", "5")),
    totp_replay: String.to_integer(System.get_env("RATE_LIMIT_TOTP_REPLAY", "1")),
    oauth_ip: String.to_integer(System.get_env("RATE_LIMIT_OAUTH_IP", "20"))

  config :estimate, EstimateWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :estimate, EstimateWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :estimate, EstimateWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Here is an example configuration for Mailgun:
  #
  #     config :estimate, Estimate.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # Most non-SMTP adapters require an API client. Swoosh supports Req, Hackney,
  # and Finch out-of-the-box. This configuration is typically done at
  # compile-time in your config/prod.exs:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Req
  #
  # See https://hexdocs.pm/swoosh/Swoosh.html#module-installation for details.
end
