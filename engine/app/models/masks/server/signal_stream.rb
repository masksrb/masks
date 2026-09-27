module Masks
  module Server
    class SignalStream < ApplicationRecord
      class Refused < StandardError; end

      include TenantScoped

      PUSH = "urn:ietf:rfc:8935".freeze
      ENABLED = "enabled".freeze
      PAUSED = "paused".freeze
      DISABLED = "disabled".freeze
      STATUSES = [ ENABLED, PAUSED, DISABLED ].freeze
      ATTEMPTS = 8
      TOKEN_TYPE = "secevent+jwt".freeze

      belongs_to :client

      encrypts :authorization_header

      validates :client_id, uniqueness: true
      validates :status, inclusion: { in: STATUSES }
      validates :issuer, presence: true
      validate :endpoint_is_callable
      validate :events_are_supported

      before_validation { self.events_requested = Array(events_requested).map(&:to_s).uniq }

      class << self
        def raised(event)
          signal = Signals.for(event)

          return if signal.nil? || event.actor.nil?

          where(status: ENABLED).includes(:client).find_each do |stream|
            next unless stream.delivers?(signal.type) && stream.follows?(event.actor, organization: Signals.organization_of(event))

            SignalJob.perform_later(stream.id, event_id: event.id)
          end
        end
      end

      def delivered_events
        events_requested & Signals::TYPES
      end

      def delivers?(type)
        receiving? && delivered_events.include?(type)
      end

      def receiving?
        !client.archived? && client.unattended_scopes.include?(Scopes::SIGNALS)
      end

      def follows?(actor, organization: nil)
        return client.tokens.exists?(actor: actor, organization: organization) if organization

        client.consents.live.exists?(actor: actor) || client.tokens.exists?(actor: actor)
      end

      def configuration
        {
          "stream_id" => uuid,
          "iss" => issuer,
          "aud" => client.client_id,
          "delivery" => { "method" => PUSH, "endpoint_url" => endpoint_url },
          "events_supported" => Signals::TYPES,
          "events_requested" => events_requested,
          "events_delivered" => delivered_events,
          "description" => description
        }.compact
      end

      def state
        { "stream_id" => uuid, "status" => status, "reason" => status_reason }.compact
      end

      def security_event_token(event)
        signal = Signals.for(event)

        sign({ signal.type => signal.payload(event) }, subject: subject_for(event.actor), at: event.created_at)
      end

      def verification_token(state)
        sign({ Signals::VERIFICATION => { "state" => state.presence }.compact }, subject: { "format" => "opaque", "id" => uuid })
      end

      def deliver!(token)
        uri = URI.parse(endpoint_url)
        headers = { "Content-Type" => "application/#{TOKEN_TYPE}", "Accept" => "application/json" }
        headers["Authorization"] = authorization_header if authorization_header.present?

        response = Outbound.post_json(uri, token, headers: headers, address: routable!(uri))

        return update_columns(last_delivered_at: Time.current, last_failure: nil) if response.is_a?(Net::HTTPSuccess)

        raise Refused, "#{client.name} answered #{response.code}"
      rescue *Outbound::UNREADABLE, URI::InvalidURIError => e
        raise Refused, "#{client.name} could not be reached: #{e.class}"
      end

      def failed!(message)
        update_columns(last_failure: message.to_s.truncate(255))
      end

      private

        def sign(events, subject:, at: Time.current)
          Issuer.new(tenant, issuer).sign({
            "iss" => issuer,
            "aud" => client.client_id,
            "jti" => SecureRandom.uuid,
            "iat" => Time.current.to_i,
            "txn" => at.to_i.to_s,
            "sub_id" => subject,
            "events" => events
          }, typ: TOKEN_TYPE)
        end

        def subject_for(actor)
          { "format" => "iss_sub", "iss" => issuer, "sub" => Subjects.for(actor, client) }
        end

        def routable!(uri)
          return if ::Rails.env.local?

          Outbound.vetted(uri) || raise(Refused, "#{client.name} resolves to an address this server will not call")
        end

        def endpoint_is_callable
          problem = Outbound.problem_with(endpoint_url)

          errors.add(:endpoint_url, problem) if problem
        end

        def events_are_supported
          unknown = events_requested - Signals::TYPES

          errors.add(:events_requested, "include events this transmitter does not send: #{unknown.join(', ')}") if unknown.any?
        end
    end
  end
end
