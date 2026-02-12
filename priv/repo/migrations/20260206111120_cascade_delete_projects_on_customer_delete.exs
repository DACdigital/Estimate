defmodule Estimate.Repo.Migrations.CascadeDeleteProjectsOnCustomerDelete do
  use Ecto.Migration

  def change do
    drop constraint(:projects, "projects_customer_id_fkey")

    alter table(:projects) do
      modify :customer_id, references(:customers, type: :binary_id, on_delete: :delete_all)
    end
  end
end
