module Manage
  module Mutations
    class RevokeConsent < BaseMutation
      argument :id, ID

      field :consent, Types::ConsentType, null: false

      def resolve(id:)
        consent = ::Consent.find_by(id: id) || refuse!("no consent with that id")

        consent.revoke!
        tokens_for(consent).find_each(&:revoke!)

        audit!(
          ::Event::CONSENT_REVOKED,
          actor: consent.actor, client: consent.client, scopes: Scopes.list(consent.scopes)
        )

        { consent: consent }
      end

      private

        def tokens_for(consent)
          RefreshToken.live.where(actor_id: consent.actor_id, client_id: consent.client_id)
        end
    end
  end
end
