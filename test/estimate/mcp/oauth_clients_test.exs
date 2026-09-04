defmodule Estimate.MCP.OAuthClientsTest do
  use Estimate.DataCase, async: true

  alias Estimate.MCP.OAuth

  describe "register_client/1" do
    test "registers a public client with defaults" do
      assert {:ok, client} =
               OAuth.register_client(%{
                 "client_name" => "Claude",
                 "redirect_uris" => ["https://claude.ai/api/mcp/auth_callback"]
               })

      assert client.name == "Claude"
      assert client.redirect_uris == ["https://claude.ai/api/mcp/auth_callback"]
      assert OAuth.get_client(client.id).id == client.id
    end

    test "defaults the name when absent" do
      assert {:ok, client} =
               OAuth.register_client(%{"redirect_uris" => ["http://localhost/callback"]})

      assert client.name == "MCP Client"
    end

    test "rejects missing, empty and invalid redirect_uris" do
      assert {:error, %Ecto.Changeset{}} = OAuth.register_client(%{"client_name" => "X"})
      assert {:error, %Ecto.Changeset{}} = OAuth.register_client(%{"redirect_uris" => []})

      assert {:error, %Ecto.Changeset{}} =
               OAuth.register_client(%{"redirect_uris" => ["http://evil.com/cb"]})
    end

    test "get_client is nil-safe on garbage ids" do
      assert OAuth.get_client("not-a-uuid") == nil
      assert OAuth.get_client(Ecto.UUID.generate()) == nil
    end

    test "client_name longer than 100 chars is rejected" do
      assert {:error, cs} =
               OAuth.register_client(%{
                 "client_name" => String.duplicate("x", 101),
                 "redirect_uris" => ["https://claude.ai/cb"]
               })

      assert %{name: [_]} = errors_on(cs)
    end

    test "more than 5 redirect uris or a uri over 2048 chars is rejected" do
      many = for i <- 1..6, do: "https://claude.ai/cb#{i}"

      assert {:error, cs} =
               OAuth.register_client(%{"client_name" => "C", "redirect_uris" => many})

      assert %{redirect_uris: [_ | _]} = errors_on(cs)

      long = "https://claude.ai/" <> String.duplicate("a", 2048)

      assert {:error, cs} =
               OAuth.register_client(%{"client_name" => "C", "redirect_uris" => [long]})

      assert %{redirect_uris: [_ | _]} = errors_on(cs)
    end
  end
end
