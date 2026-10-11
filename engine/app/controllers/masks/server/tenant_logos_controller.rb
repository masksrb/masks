module Masks
  module Server
    class TenantLogosController < ApplicationController
      include ServesPictures

      skip_before_action :refuse_blocked_device, only: :show

      def show
        digest = current_tenant.logo_digest
        return head(:not_found) if digest.blank?

        stamped = digest.present? && params[:v] == digest
        caching = stamped ? "public, max-age=#{FOREVER}, immutable" : "public, max-age=#{BRIEFLY}"

        deliver_picture(digest, cache_control: caching) do
          [ Pictures::CONTENT_TYPE, TenantLogo.find_by(tenant_id: current_tenant.id)&.resized(Avatars.size(params[:size])) ]
        end
      end
    end
  end
end
