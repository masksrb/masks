module Masks
  module Server
    module MailedLink
      extend ActiveSupport::Concern

      class_methods do
        def path(segment = nil)
          @path = segment if segment

          @path
        end

        def open!(actor:, by: nil, **held)
          where(actor_id: actor.id).live.find_each(&:consume!)

          mint!(actor: actor, payload: { "email" => actor.email }.merge(held.stringify_keys, { "by" => by&.uuid }.compact))
        end
      end

      def address
        (payload || {})["email"]
      end

      def addressed?
        address.present? && actor.email.present? && actor.email == address
      end

      def opened_by
        uuid = (payload || {})["by"]

        @opened_by ||= uuid && Actor.find_by(uuid: uuid)
      end

      def url(origin)
        "#{origin}/#{self.class.path}/#{secret}"
      end

      def delivered!
        update!(payload: (payload || {}).merge("delivered" => true))
      end

      def delivered?
        (payload || {})["delivered"].present?
      end
    end
  end
end
