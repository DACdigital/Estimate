defmodule Estimate.Emails.InviteEmail do
  import Swoosh.Email

  def invite_email(org, invite, inviter_name) do
    from_name = org.smtp_from_name || org.name
    invite_url = EstimateWeb.Endpoint.url() <> "/invites/#{invite.token}"
    org_name = html_escape(org.name)
    inviter = html_escape(inviter_name)
    role = html_escape(invite.role)
    expires = Calendar.strftime(invite.expires_at, "%B %d, %Y")

    new()
    |> from({from_name, org.smtp_from_email})
    |> to(invite.email)
    |> subject("You've been invited to join #{org.name}")
    |> html_body(html_body(org_name, inviter, role, invite_url, expires))
    |> text_body(text_body(org.name, inviter_name, invite.role, invite_url, expires))
  end

  def test_email(org, to_email) do
    from_name = org.smtp_from_name || org.name

    new()
    |> from({from_name, org.smtp_from_email})
    |> to(to_email)
    |> subject("Test email from #{org.name}")
    |> html_body("""
    <div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; max-width: 480px; margin: 0 auto; padding: 40px 20px;">
      <h2 style="color: #111827; margin: 0 0 8px;">SMTP is working!</h2>
      <p style="color: #6b7280; font-size: 14px; margin: 0;">
        This test email was sent from <strong>#{html_escape(org.name)}</strong>.
        Your email settings are configured correctly.
      </p>
    </div>
    """)
    |> text_body("SMTP is working! This test email was sent from #{org.name}.")
  end

  defp html_body(org_name, inviter, role, invite_url, expires) do
    """
    <!DOCTYPE html>
    <html>
    <head><meta charset="utf-8"></head>
    <body style="margin: 0; padding: 0; background-color: #f9fafb; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;">
      <table width="100%" cellpadding="0" cellspacing="0" style="background-color: #f9fafb; padding: 40px 20px;">
        <tr>
          <td align="center">
            <table width="480" cellpadding="0" cellspacing="0" style="background-color: #ffffff; border-radius: 12px; border: 1px solid #e5e7eb; overflow: hidden;">
              <tr>
                <td style="padding: 40px 32px 32px;">
                  <h1 style="margin: 0 0 4px; font-size: 20px; font-weight: 700; color: #111827;">
                    #{org_name}
                  </h1>
                  <p style="margin: 0 0 24px; font-size: 14px; color: #6b7280;">
                    Team invitation
                  </p>
                  <p style="margin: 0 0 24px; font-size: 15px; color: #374151; line-height: 1.6;">
                    <strong>#{inviter}</strong> has invited you to join
                    <strong>#{org_name}</strong> as a <strong>#{role}</strong>.
                  </p>
                  <table cellpadding="0" cellspacing="0" style="margin: 0 0 24px;">
                    <tr>
                      <td style="background-color: #111827; border-radius: 8px;">
                        <a href="#{invite_url}" style="display: inline-block; padding: 12px 32px; color: #ffffff; font-size: 14px; font-weight: 600; text-decoration: none;">
                          Accept Invitation
                        </a>
                      </td>
                    </tr>
                  </table>
                  <p style="margin: 0; font-size: 12px; color: #9ca3af;">
                    This invitation expires on #{expires}.
                  </p>
                </td>
              </tr>
              <tr>
                <td style="padding: 16px 32px; background-color: #f9fafb; border-top: 1px solid #e5e7eb;">
                  <p style="margin: 0; font-size: 12px; color: #9ca3af;">
                    If you didn't expect this invitation, you can safely ignore this email.
                  </p>
                </td>
              </tr>
            </table>
          </td>
        </tr>
      </table>
    </body>
    </html>
    """
  end

  defp text_body(org_name, inviter, role, invite_url, expires) do
    """
    #{inviter} has invited you to join #{org_name} as a #{role}.

    Accept the invitation: #{invite_url}

    This invitation expires on #{expires}.

    If you didn't expect this invitation, you can safely ignore this email.
    """
  end

  defp html_escape(nil), do: ""

  defp html_escape(text) do
    text
    |> to_string()
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end
end
