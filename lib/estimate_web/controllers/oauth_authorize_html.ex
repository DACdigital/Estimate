defmodule EstimateWeb.OAuthAuthorizeHTML do
  use EstimateWeb, :html

  alias Estimate.MCP.OAuth.Scopes

  embed_templates "oauth_authorize_html/*"
end
