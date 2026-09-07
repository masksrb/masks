class RefreshAuthenticatorsJob < ApplicationJob
  queue_as :maintenance
  across_tenants!

  def perform(store: FidoMetadata::Store.new)
    Authenticators.refresh!(store: store)
  rescue Authenticators::Unreachable => e
    Rails.logger.warn("authenticator metadata was not refreshed: #{e.message}")
  end
end
