module Masks
  module Server
    module ClientAuthentication
      extend ActiveSupport::Concern

      private

        def authenticated_client
          assertion = params[:client_assertion].presence

          return asserted_client(assertion) if assertion || params[:client_assertion_type].present?

          id, secret = presented_credentials
          client = Client.authenticating(id) if id.present?

          client_refused!("no client is registered with that client_id") if client.nil?
          client_refused!("this client authenticates with a signed assertion, not a secret") if client.asserts?

          client_refused! unless client.authenticate_secret(secret)

          client
        end

        def asserted_client(assertion)
          client_refused!("client_assertion_type must be #{ClientAssertion::TYPE}") unless params[:client_assertion_type] == ClientAssertion::TYPE
          client_refused!("client_assertion is required") if assertion.blank?
          client_refused!("a client authenticates one way at a time") if request.authorization.to_s.start_with?("Basic ") || params[:client_secret].present?

          named = ClientAssertion.issuer_of(assertion)
          id = params[:client_id].presence || named

          client_refused!("client_id does not match the client assertion") if params[:client_id].present? && named != params[:client_id]

          client = Client.authenticating(id) if id.present?

          client_refused!("no client is registered with that client_id") if client.nil?
          client_refused!("this client is not registered to authenticate with a signed assertion") unless client.asserts?

          ClientAssertion.new(assertion, client: client, audiences: assertion_audiences).verify!

          client
        rescue ClientAssertion::Refused => e
          client_refused!(e.message)
        end

        def assertion_audiences
          [ issuer.url, "#{issuer.url}/token", "#{issuer.url}#{request.path}" ].uniq
        end

        def presented_credentials
          header = request.authorization.to_s

          if header.start_with?("Basic ")
            Base64.decode64(header.split(" ", 2).last.to_s).split(":", 2).map { |p| CGI.unescape(p.to_s) }
          else
            [ params[:client_id], params[:client_secret] ]
          end
        end

        def client_refused!(description = "client authentication failed")
          raise Policy::Denied.new("invalid_client", description, status: :unauthorized)
        end
    end
  end
end
