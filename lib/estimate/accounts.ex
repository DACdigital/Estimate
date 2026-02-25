defmodule Estimate.Accounts do
  @moduledoc """
  The Accounts context handles users, sessions, authentication, and org registration.
  Organization management is in `Estimate.Organizations`.
  Currency management is in `Estimate.Organizations.Currencies`.
  """

  import Ecto.Query
  alias Estimate.Repo

  alias Estimate.Accounts.{
    User,
    Organization,
    Membership,
    UserToken,
    Currency,
    RoleTemplate,
    RoleTemplateRate
  }

  ## User queries

  def get_user!(id), do: Repo.get!(User, id)

  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = get_user_by_email(email)
    if User.valid_password?(user, password), do: user
  end

  ## Registration with organization

  def register_user_with_organization(user_attrs, org_attrs) do
    Ecto.Multi.new()
    |> Ecto.Multi.insert(:user, User.registration_changeset(%User{}, user_attrs))
    |> Ecto.Multi.insert(:organization, Organization.changeset(%Organization{}, org_attrs))
    |> Ecto.Multi.insert(:membership, fn %{user: user, organization: org} ->
      Membership.changeset(%Membership{}, %{
        user_id: user.id,
        organization_id: org.id,
        role: "owner"
      })
    end)
    |> Ecto.Multi.run(:set_org_context, fn _repo, %{organization: org} ->
      Repo.query!("SELECT set_config('app.current_org_id', $1, true)", [org.id])
      {:ok, :context_set}
    end)
    |> Ecto.Multi.run(:currencies, fn _repo, %{organization: org} ->
      case seed_default_currencies(org.id) do
        :ok -> {:ok, :seeded}
        {:error, changeset} -> {:error, changeset}
      end
    end)
    |> Ecto.Multi.run(:role_templates, fn _repo, %{organization: org} ->
      case seed_default_role_templates(org.id) do
        :ok -> {:ok, :seeded}
        {:error, changeset} -> {:error, changeset}
      end
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user, organization: org, membership: membership}} ->
        {:ok, %{user: user, organization: org, membership: membership}}

      {:error, :user, changeset, _} ->
        {:error, :user, changeset}

      {:error, :organization, changeset, _} ->
        {:error, :organization, changeset}

      {:error, :membership, changeset, _} ->
        {:error, :membership, changeset}
    end
  end

  @doc """
  Creates an organization with the given user as owner.
  Also seeds default currencies and role templates.
  """
  def create_organization_with_owner(org_attrs, user_id) do
    Ecto.Multi.new()
    |> Ecto.Multi.insert(:organization, Organization.changeset(%Organization{}, org_attrs))
    |> Ecto.Multi.insert(:membership, fn %{organization: org} ->
      Membership.changeset(%Membership{}, %{
        user_id: user_id,
        organization_id: org.id,
        role: "owner"
      })
    end)
    |> Ecto.Multi.run(:set_org_context, fn _repo, %{organization: org} ->
      Repo.query!("SELECT set_config('app.current_org_id', $1, true)", [org.id])
      {:ok, :context_set}
    end)
    |> Ecto.Multi.run(:currencies, fn _repo, %{organization: org} ->
      case seed_default_currencies(org.id) do
        :ok -> {:ok, :seeded}
        {:error, changeset} -> {:error, changeset}
      end
    end)
    |> Ecto.Multi.run(:role_templates, fn _repo, %{organization: org} ->
      case seed_default_role_templates(org.id) do
        :ok -> {:ok, :seeded}
        {:error, changeset} -> {:error, changeset}
      end
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{organization: org}} -> {:ok, org}
      {:error, :organization, changeset, _} -> {:error, changeset}
      {:error, :membership, changeset, _} -> {:error, changeset}
    end
  end

  def find_or_create_oauth_user(%{email: email} = attrs) do
    case get_user_by_email(email) do
      %User{} = user ->
        {:ok, user}

      nil ->
        %User{}
        |> User.oauth_registration_changeset(attrs)
        |> Repo.insert()
    end
  end

  def register_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  def change_user_registration(%User{} = user, attrs \\ %{}) do
    User.registration_changeset(user, attrs, hash_password: false, validate_email: false)
  end

  ## Last org tracking

  def update_user_last_org(%User{last_org_id: org_id}, org_id), do: :ok

  def update_user_last_org(%User{} = user, org_id) do
    Repo.without_rls(fn ->
      user
      |> Ecto.Changeset.change(last_org_id: org_id)
      |> Repo.update()
    end)
  end

  ## Session

  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  def delete_user_session_token(token) do
    Repo.delete_all(UserToken.by_token_and_context_query(token, "session"))
    :ok
  end

  ## Confirmation

  def deliver_user_confirmation_instructions(%User{} = user, confirmation_url_fun)
      when is_function(confirmation_url_fun, 1) do
    if user.confirmed_at do
      {:error, :already_confirmed}
    else
      {encoded_token, user_token} = UserToken.build_email_token(user, "confirm")
      Repo.insert!(user_token)
      {:ok, encoded_token}
    end
  end

  def confirm_user(token) do
    with {:ok, query} <- UserToken.verify_email_token_query(token, "confirm"),
         %User{} = user <- Repo.one(query),
         {:ok, %{user: user}} <- Repo.transaction(confirm_user_multi(user)) do
      {:ok, user}
    else
      _ -> :error
    end
  end

  defp confirm_user_multi(user) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, User.confirm_changeset(user))
    |> Ecto.Multi.delete_all(:tokens, UserToken.by_user_and_contexts_query(user, ["confirm"]))
  end

  ## Reset password

  def deliver_user_reset_password_instructions(%User{} = user, reset_password_url_fun)
      when is_function(reset_password_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "reset_password")
    Repo.insert!(user_token)
    {:ok, encoded_token}
  end

  def get_user_by_reset_password_token(token) do
    with {:ok, query} <- UserToken.verify_email_token_query(token, "reset_password"),
         %User{} = user <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  def reset_user_password(user, attrs) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, User.password_changeset(user, attrs))
    |> Ecto.Multi.delete_all(:tokens, UserToken.by_user_and_contexts_query(user, :all))
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, :user, changeset, _} -> {:error, changeset}
    end
  end

  ## Settings

  def change_user_email(user, attrs \\ %{}) do
    User.email_changeset(user, attrs, validate_email: false)
  end

  def apply_user_email(user, password, attrs) do
    user
    |> User.email_changeset(attrs)
    |> User.validate_current_password(password)
    |> Ecto.Changeset.apply_action(:update)
  end

  def change_user_password(user, attrs \\ %{}) do
    User.password_changeset(user, attrs, hash_password: false)
  end

  def update_user_password(user, password, attrs) do
    changeset =
      user
      |> User.password_changeset(attrs)
      |> User.validate_current_password(password)

    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, changeset)
    |> Ecto.Multi.delete_all(:tokens, UserToken.by_user_and_contexts_query(user, :all))
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, :user, changeset, _} -> {:error, changeset}
    end
  end

  ## Role Templates

  def list_role_templates(org_id) do
    Repo.ensure_org_context(fn ->
      from(rt in RoleTemplate,
        where: rt.organization_id == ^org_id,
        preload: [rates: :currency],
        order_by: [asc: rt.position, asc: rt.name]
      )
      |> Repo.all()
    end)
  end

  def get_role_template!(id, org_id) do
    Repo.ensure_org_context(fn ->
      from(rt in RoleTemplate, where: rt.id == ^id and rt.organization_id == ^org_id)
      |> Repo.one!()
      |> Repo.preload(rates: :currency)
    end)
  end

  def list_role_templates_by_ids(template_ids) when is_list(template_ids) do
    Repo.ensure_org_context(fn ->
      from(rt in RoleTemplate,
        where: rt.id in ^template_ids,
        preload: [rates: :currency],
        order_by: [asc: rt.position, asc: rt.name]
      )
      |> Repo.all()
    end)
  end

  def create_role_template(org_id, attrs) do
    Repo.ensure_org_context(fn ->
      %RoleTemplate{}
      |> RoleTemplate.changeset(Map.put(attrs, :organization_id, org_id))
      |> Repo.insert()
      |> case do
        {:ok, template} -> {:ok, Repo.preload(template, rates: :currency)}
        error -> error
      end
    end)
  end

  def update_role_template(%RoleTemplate{} = template, attrs) do
    Repo.ensure_org_context(fn ->
      template
      |> RoleTemplate.changeset(attrs)
      |> Repo.update()
      |> case do
        {:ok, template} -> {:ok, Repo.preload(template, [rates: :currency], force: true)}
        error -> error
      end
    end)
  end

  def delete_role_template(%RoleTemplate{} = template) do
    Repo.ensure_org_context(fn ->
      Repo.delete(template)
    end)
  end

  def change_role_template(%RoleTemplate{} = template, attrs \\ %{}) do
    RoleTemplate.changeset(template, attrs)
  end

  ## Role Template Rates

  def get_role_template_rate!(id, org_id) do
    Repo.ensure_org_context(fn ->
      from(r in RoleTemplateRate,
        join: rt in RoleTemplate,
        on: r.role_template_id == rt.id,
        where: r.id == ^id and rt.organization_id == ^org_id
      )
      |> Repo.one!()
    end)
  end

  def get_role_template_rate(template_id, currency_id) do
    Repo.ensure_org_context(fn ->
      Repo.get_by(RoleTemplateRate, role_template_id: template_id, currency_id: currency_id)
    end)
  end

  def create_role_template_rate(template_id, currency_id, hourly_rate) do
    Repo.ensure_org_context(fn ->
      %RoleTemplateRate{}
      |> RoleTemplateRate.changeset(%{
        role_template_id: template_id,
        currency_id: currency_id,
        hourly_rate: hourly_rate
      })
      |> Repo.insert()
    end)
  end

  def update_role_template_rate(%RoleTemplateRate{} = rate, attrs) do
    Repo.ensure_org_context(fn ->
      rate
      |> RoleTemplateRate.changeset(attrs)
      |> Repo.update()
    end)
  end

  def delete_role_template_rate(%RoleTemplateRate{} = rate) do
    Repo.ensure_org_context(fn -> Repo.delete(rate) end)
  end

  ## Seeding (used during org creation)

  def seed_default_currencies(org_id) do
    Currency.default_currencies()
    |> Enum.reduce_while(:ok, fn attrs, :ok ->
      %Currency{}
      |> Currency.changeset(Map.put(attrs, :organization_id, org_id))
      |> Repo.insert()
      |> case do
        {:ok, _} -> {:cont, :ok}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
  end

  def seed_default_role_templates(org_id) do
    main_currency = Estimate.Organizations.Currencies.get_main_currency(org_id)

    RoleTemplate.default_templates()
    |> Enum.reduce_while(:ok, fn attrs, :ok ->
      with {:ok, template} <-
             %RoleTemplate{}
             |> RoleTemplate.changeset(%{
               name: attrs.name,
               abbreviation: attrs.abbreviation,
               position: attrs.position,
               organization_id: org_id
             })
             |> Repo.insert(),
           :ok <- maybe_create_template_rate(template, main_currency, attrs.default_rate) do
        {:cont, :ok}
      else
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
  end

  defp maybe_create_template_rate(_template, nil, _rate), do: :ok

  defp maybe_create_template_rate(template, currency, default_rate) do
    %RoleTemplateRate{}
    |> RoleTemplateRate.changeset(%{
      role_template_id: template.id,
      currency_id: currency.id,
      hourly_rate: Decimal.new(default_rate)
    })
    |> Repo.insert()
    |> case do
      {:ok, _} -> :ok
      {:error, changeset} -> {:error, changeset}
    end
  end
end
