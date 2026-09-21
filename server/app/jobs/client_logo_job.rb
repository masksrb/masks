class ClientLogoJob < ApplicationJob
  queue_as :maintenance

  discard_on ActiveRecord::RecordNotFound

  def perform(client_id)
    client = Client.find(client_id)

    ClientLogo.fetch!(client)
  rescue Outbound::Refused, Pictures::Unreadable, URI::InvalidURIError => e
    ClientLogo.forget(client)

    Event.record!(Event::CLIENT_LOGO_REFUSED, actor: nil, by: nil, client: client, said: e.message)
  end
end
