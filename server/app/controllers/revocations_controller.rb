class RevocationsController < ApplicationController
  include TokenPresented

  def create
    client = authenticate_client!
    token = presented_token

    if token && token.client_id == client.id
      revoked = token.revoke!

      Event.record!(
        Event::TOKEN_REVOKED,
        actor: token.actor, by: nil, client: client,
        kind: token.class.name.underscore, revoked: revoked
      )
    end

    head :ok
  end
end
