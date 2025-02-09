# Preview all emails at http://localhost:3000/rails/mailers/login_link_mailer
class LoginLinkMailerPreview < ActionMailer::Preview
  def authenticate
    LoginLinkMailer.with(login_link:).authenticate
  end

  def verify
    LoginLinkMailer.with(login_link:).verify
  end

  private

  def login_link
    actor = Masks::Actor.first
    email = Masks::Email.build(address: "mailer@example.com", actor:)

    Masks::LoginLink.build(
      settings: {
        path: "/test",
        params: {
        },
      },
      client: manage_client,
      device: Masks::Device.first,
      email:,
      actor:,
    )
  end
end
