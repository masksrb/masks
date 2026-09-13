class ProviderMetadataController < ApplicationController
  def show
    provider = Provider.active.find_by(key: params[:key].to_s, protocol: Provider::SAML)

    return head :not_found if provider.nil?

    render xml: provider.federation.metadata(callback: Linking.callback_for(provider))
  end
end
