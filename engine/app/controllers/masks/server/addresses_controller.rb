module Masks
  module Server
    class AddressesController < ApplicationController
      rate_limit to: ::Rails.configuration.masks.account_attempt_limit,
                 within: 3.minutes,
                 by: -> { [ current_tenant.id, current_actor&.id ].join(":") },
                 with: -> { refuse(t("addresses.too_many_attempts")) },
                 only: :update

      before_action :require_actor
      before_action -> { reauthenticated!(anchor, t("addresses.again")) }
      before_action :refuse_directed

      def create
        address = Addresses.normalize(channel, params[:address])

        return refuse(t("addresses.#{channel}.invalid")) if address.nil?
        return refuse(t("addresses.#{channel}.same")) if address.casecmp?(current_actor.public_send(channel).to_s)
        return refuse(t("addresses.#{channel}.undeliverable")) unless Addresses.deliverable?(channel)
        return refuse(t("addresses.too_many_requests")) if ConfirmationCode.crowded?(actor: current_actor, channel: channel)

        token = Addresses.request!(current_actor, channel, address, journey: Journey.account(current_actor))
        Addresses.hold(session, current_actor, channel, token)

        redirect_to root_path(anchor: anchor), notice: t("addresses.#{channel}.sent", to: address)
      end

      def update
        token = Addresses.pending(session, current_actor)[channel]

        return refuse(t("addresses.expired")) if token.nil?

        case Addresses.confirm!(current_actor, token, params[:code].to_s)
        when :invalid then refuse(t("addresses.invalid_code"))
        when :taken
          Addresses.hold(session, current_actor, channel, nil)
          refuse(t("addresses.#{channel}.taken"))
        else
          Addresses.hold(session, current_actor, channel, nil)
          redirect_to root_path(anchor: anchor), notice: t("addresses.#{channel}.changed")
        end
      end

      def destroy
        return refuse(t("addresses.phone.none")) if current_actor.phone.blank?
        return refuse(t("addresses.phone.required")) if SignInPolicy.for(tenant: current_tenant).requires?(:phone)

        current_actor.update!(phone: nil, phone_verified_at: nil)
        Addresses.hold(session, current_actor, channel, nil)
        Event.record!(Event::PHONE_REMOVED, actor: current_actor)

        redirect_to root_path(anchor: anchor), notice: t("addresses.phone.removed")
      end

      private

        def channel
          params[:channel].to_s
        end

        def anchor
          channel == ConfirmationCode::PHONE ? "phone" : "email"
        end

        def require_actor
          redirect_to login_path unless current_actor
        end

        def refuse_directed
          refuse(t("addresses.directed")) if current_actor.directed?
        end

        def refuse(message)
          redirect_to root_path(anchor: anchor), alert: message
        end
    end
  end
end
