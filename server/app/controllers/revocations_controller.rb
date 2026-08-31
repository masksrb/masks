class RevocationsController < ApplicationController
  include TokenPresented

  def create
    client = authenticate_client!
    token = presented_token

    token.revoke! if token && token.client_id == client.id

    head :ok
  end
end
