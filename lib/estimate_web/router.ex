defmodule EstimateWeb.Router do
  use EstimateWeb, :router

  import EstimateWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {EstimateWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Health check endpoints (no auth, no session)
  scope "/", EstimateWeb do
    pipe_through :api
    get "/health", HealthController, :liveness
    get "/healthz", HealthController, :liveness
    get "/readyz", HealthController, :readiness

    get "/.well-known/oauth-authorization-server", OAuthMetadataController, :authorization_server
    get "/.well-known/oauth-protected-resource", OAuthMetadataController, :protected_resource
    get "/.well-known/oauth-protected-resource/mcp", OAuthMetadataController, :protected_resource
  end

  # MCP server (Streamable HTTP). Auth handled inside the plug via
  # bearer API keys — no session, no CSRF.
  forward "/mcp", Anubis.Server.Transport.StreamableHTTP.Plug, server: EstimateWeb.MCPServer

  # Auth routes - redirect if authenticated
  scope "/", EstimateWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    live_session :redirect_if_user_is_authenticated,
      layout: {EstimateWeb.Layouts, :auth},
      on_mount: [{EstimateWeb.UserAuth, :redirect_if_user_is_authenticated}] do
      live "/users/register", UserLive.Registration, :new
      live "/users/log_in", UserLive.Login, :new
      live "/users/reset_password", UserLive.ForgotPassword, :new
      live "/users/reset_password/:token", UserLive.ResetPassword, :edit
    end

    post "/users/log_in", UserSessionController, :create
    get "/", UserSessionController, :redirect_to_login
    get "/auth/google", GoogleAuthController, :request
    get "/auth/google/callback", GoogleAuthController, :callback
  end

  # Two-factor verification (pending 2FA — neither fully logged in nor anonymous)
  scope "/", EstimateWeb do
    pipe_through :browser

    live_session :two_factor_verification,
      layout: {EstimateWeb.Layouts, :auth},
      on_mount: [{EstimateWeb.UserAuth, :require_pending_2fa}] do
      live "/users/two-factor", UserLive.TotpVerification, :verify
    end

    post "/users/two-factor/verify", UserSessionController, :verify_totp
  end

  # Invite acceptance (special - needs to handle both logged in and anonymous)
  scope "/", EstimateWeb do
    pipe_through :browser

    live_session :invite_acceptance,
      layout: {EstimateWeb.Layouts, :auth},
      on_mount: [{EstimateWeb.UserAuth, :mount_current_user}] do
      live "/invites/:token", InviteLive.Accept, :show
    end

    live_session :join_request,
      layout: {EstimateWeb.Layouts, :auth},
      on_mount: [{EstimateWeb.UserAuth, :mount_current_user}] do
      live "/organizations/:id/join", JoinRequestLive.New, :new
    end
  end

  # Account settings (non-org, own layout)
  scope "/", EstimateWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :account_settings,
      layout: {EstimateWeb.Layouts, :app_account},
      on_mount: [{EstimateWeb.UserAuth, :ensure_authenticated}] do
      live "/account", UserLive.AccountSettings, :index
      live "/account/two-factor/setup", UserLive.TotpSetup, :setup
    end
  end

  # Authenticated routes (non-org)
  scope "/", EstimateWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      layout: {EstimateWeb.Layouts, :auth},
      on_mount: [{EstimateWeb.UserAuth, :ensure_authenticated}] do
      live "/organizations", OrganizationLive.Index, :index
      live "/organizations/new", OrganizationLive.Index, :new
    end

    delete "/users/log_out", UserSessionController, :delete
  end

  # Organization-scoped routes
  scope "/org/:org_id", EstimateWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :org_scoped,
      layout: {EstimateWeb.Layouts, :app},
      on_mount: [
        {EstimateWeb.UserAuth, :ensure_authenticated},
        {EstimateWeb.OrgAuth, :ensure_org_member}
      ] do
      # Dashboard
      live "/", DashboardLive.Index, :index

      # Roles (top-level nav)
      live "/roles", RolesLive.Index, :index

      # Estimation Templates
      live "/templates", TemplatesLive.Index, :index
      live "/templates/:id", TemplatesLive.Show, :show

      # Settings
      live "/settings", SettingsLive.Index, :index
      live "/settings/members", SettingsLive.Members, :index
      live "/settings/currencies", SettingsLive.Currencies, :index
      live "/settings/ai", SettingsLive.Ai, :index
      live "/settings/email", SettingsLive.Email, :index
      live "/settings/mcp", SettingsLive.Mcp, :index
      live "/settings/trash", SettingsLive.Trash, :index

      # CRM
      live "/customers", CustomerLive.Index, :index
      live "/customers/new", CustomerLive.Index, :new
      live "/customers/:id/edit", CustomerLive.Index, :edit
      live "/customers/:id", CustomerLive.Show, :show

      # Portfolio
      live "/projects", ProjectLive.Index, :index
      live "/projects/new", ProjectLive.Index, :new
      live "/projects/:id/edit", ProjectLive.Index, :edit
      live "/projects/:id", ProjectLive.Show, :show
      live "/projects/:id/collaborators", ProjectLive.Show, :collaborators
      live "/projects/:id/estimations", ProjectLive.Show, :estimations
      live "/projects/:id/estimations/new", ProjectLive.Show, :new_estimation

      # Estimations
      live "/projects/:project_id/estimations/:id/estimator", EstimatorLive.Index, :index
    end
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:estimate, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: EstimateWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
