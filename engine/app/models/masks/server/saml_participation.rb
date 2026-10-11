module Masks
  module Server
    class SamlParticipation < ApplicationRecord
      include TenantScoped

      belongs_to :session
      belongs_to :client

      scope :unnotified, -> { where(notified_at: nil) }
      scope :listening, -> { joins(:client).merge(Client.speaking(SamlIdentity::PROTOCOL)).where.not(clients: { saml_slo_url: [ nil, "" ] }) }

      class << self
        def record!(session:, client:, name_id:, name_id_format:)
          participation = find_or_initialize_by(session: session, client: client)
          participation.update!(name_id: name_id, name_id_format: name_id_format,
                                session_index: SamlIdentity.session_index(session), notified_at: nil)
          participation
        end

        def claim!(scope)
          scope.unnotified.listening.includes(:client).order(:id).select(&:claimed?)
        end
      end

      def claimed?
        self.class.where(id: id, notified_at: nil).update_all(notified_at: Time.current) == 1
      end

      def sign_off(issuer)
        SamlIdentity::SignOff.new(issuer: issuer, client: client, name_id: name_id, name_id_format: name_id_format,
                                  session_index: session_index)
      end
    end
  end
end
