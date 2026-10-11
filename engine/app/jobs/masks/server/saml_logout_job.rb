module Masks
  module Server
    class SamlLogoutJob < ApplicationJob
      queue_as :logout

      retry_on BackchannelLogout::Refused, wait: :polynomially_longer, attempts: 5 do |job, error|
        job.gave_up!(error)
      end

      def perform(client_id:, name_id:, name_id_format:, session_index:, origin:, actor: nil)
        client = Client.speaking(SamlIdentity::PROTOCOL).find_by(client_id: client_id)

        return if client.nil? || client.saml_slo_url.blank?

        BackchannelLogout.deliver_saml!(
          SamlIdentity::SignOff.new(
            issuer: Issuer.new(Current.tenant, origin), client: client,
            name_id: name_id, name_id_format: name_id_format, session_index: session_index
          )
        )
      end

      def gave_up!(error)
        held = arguments.first.to_h.symbolize_keys

        Tenant.switch(held_tenant) do
          Event.record!(
            Event::LOGOUT_UNDELIVERED,
            actor: Subjects.locate(held[:actor]), by: nil,
            client: Client.find_by(client_id: held[:client_id]),
            device: nil, ip_address: nil, user_agent: nil,
            said: error.message
          )
        end
      end
    end
  end
end
