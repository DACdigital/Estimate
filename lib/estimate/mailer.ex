defmodule Estimate.Mailer do
  use Swoosh.Mailer, otp_app: :estimate

  alias Estimate.Organizations

  def deliver_with_org_smtp(%Swoosh.Email{} = email, org) do
    password = Organizations.get_decrypted_smtp_password(org)

    config = [
      relay: org.smtp_host,
      port: org.smtp_port || 587,
      username: org.smtp_username,
      password: password,
      tls: :always,
      auth: :always,
      ssl: org.smtp_port == 465
    ]

    Swoosh.Adapters.SMTP.deliver(email, config)
  end
end
