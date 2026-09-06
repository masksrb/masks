class BackchannelLogoutJob < ApplicationJob
  queue_as :logout

  retry_on BackchannelLogout::Refused, wait: :polynomially_longer, attempts: 5 do |job, error|
    job.gave_up!(error)
  end

  def perform(client_id:, subject:, sid:, origin:)
    client = Client.active.find_by(client_id: client_id)

    return if client.nil? || !client.notified_on_logout?

    issuer = Issuer.new(Current.tenant, origin)

    BackchannelLogout.deliver!(
      client,
      issuer.logout_token(client: client, subject: subject, sid: sid)
    )
  end

  def gave_up!(error)
    held = arguments.first.to_h.symbolize_keys

    Tenant.switch(held_tenant) do
      Event.record!(
        Event::LOGOUT_UNDELIVERED,
        actor: Actor.find_by(uuid: held[:subject]), by: nil,
        client: Client.find_by(client_id: held[:client_id]),
        device: nil, ip_address: nil, user_agent: nil,
        said: error.message
      )
    end
  end
end
