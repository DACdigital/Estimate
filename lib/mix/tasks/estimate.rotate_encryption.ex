defmodule Mix.Tasks.Estimate.RotateEncryption do
  @moduledoc """
  Re-encrypts all stored secrets with the current ENCRYPTION_KEY. Idempotent.

      mix estimate.rotate_encryption
  """
  use Mix.Task

  @shortdoc "Re-encrypt stored secrets with the current key"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    if Estimate.Encryption.current_version() == 1 do
      Mix.shell().info("ENCRYPTION_KEY not configured; nothing to rotate")
    else
      %{users: u, users_failed: uf, organizations: o, organizations_failed: of} =
        Estimate.Encryption.Rotation.run()

      Mix.shell().info(
        "Rotated #{u} user secret(s) and #{o} organization(s) to key v#{Estimate.Encryption.current_version()}."
      )

      if uf > 0 or of > 0 do
        Mix.shell().error(
          "#{uf} user secret(s) and #{of} organization(s) failed to re-encrypt; see logs for details."
        )

        Mix.raise("estimate.rotate_encryption: #{uf + of} row(s) failed to rotate")
      end
    end
  end
end
