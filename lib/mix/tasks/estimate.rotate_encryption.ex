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

    %{users: u, organizations: o} = Estimate.Encryption.Rotation.run()

    Mix.shell().info(
      "Rotated #{u} user secret(s) and #{o} organization(s) to key v#{Estimate.Encryption.current_version()}."
    )
  end
end
