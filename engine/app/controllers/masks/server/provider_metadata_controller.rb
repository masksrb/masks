module Masks
  module Server
    class ProviderMetadataController < ApplicationController
      def show
        provider = Provider.active.find_by(key: params[:key].to_s, protocol: Provider::SAML)

        return head :not_found if provider.nil?

        render xml: provider.federation.metadata(callback: provider.callback_url)
      end
    end
  end
end
