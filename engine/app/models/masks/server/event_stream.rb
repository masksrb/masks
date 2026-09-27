module Masks
  module Server
    class EventStream < ApplicationRecord
      class Refused < StandardError; end

      include TenantScoped
      include Archivable

      TOLERANCE = 5.minutes
      ATTEMPTS = 8
      UNSTREAMED = [ Event::STREAM_FAILED ].freeze

      belongs_to :organization, optional: true

      encrypts :secret

      validates :key, presence: true,
                      uniqueness: { scope: :tenant_id },
                      format: { with: /\A[a-z0-9][a-z0-9-]*\z/ }
      validates :name, presence: true
      validate :url_is_callable
      validate :actions_are_known

      before_validation :issue_secret, on: :create
      before_validation { self.actions = Array(actions).map(&:to_s).uniq.sort }

      class << self
        def raised(event)
          return false if UNSTREAMED.include?(event.action)

          streams = active.select { |stream| stream.streams?(event) }

          streams.each { |stream| EventStreamJob.perform_later(stream.id, event.id) }

          streams.any?
        end

        def sign(secret, timestamp, body)
          OpenSSL::HMAC.hexdigest("SHA256", secret, "#{timestamp}.#{body}")
        end

        def verified?(secret, header, body, now: Time.current)
          parts = header.to_s.split(",").filter_map { |part| part.split("=", 2).then { |k, v| [ k, v ] if v } }.to_h
          timestamp = parts["t"]

          return false unless timestamp&.match?(/\A\d+\z/) && parts["v1"]
          return false if (now.to_i - timestamp.to_i).abs > TOLERANCE

          ActiveSupport::SecurityUtils.secure_compare(parts["v1"], sign(secret, timestamp, body))
        end
      end

      def streams?(event)
        return false if organization_id && event.organization_id != organization_id

        actions.empty? || actions.include?(event.action)
      end

      def rotate_secret!
        update!(secret: SecureRandom.hex(32))
      end

      def deliver!(event)
        post!(payload(event), action: event.action, delivery: event.id)
      end

      def ping!
        post!({ id: nil, tenant: tenant.subdomain, action: "stream.tested", created_at: Time.current.iso8601 },
              action: "stream.tested", delivery: nil)
      end

      def delivered!
        update_columns(last_delivered_at: Time.current, last_failure: nil)
      end

      def failed!(message)
        update_columns(last_failure: message.to_s.truncate(255))
      end

      def payload(event)
        event.exported(tenant)
      end

      private

        def post!(body, action:, delivery:)
          uri = URI.parse(url)
          json = body.to_json
          timestamp = Time.current.to_i

          response = Outbound.post_json(
            uri, json,
            headers: {
              "Masks-Event" => action,
              "Masks-Delivery" => delivery.to_s,
              "Masks-Signature" => "t=#{timestamp},v1=#{self.class.sign(secret, timestamp, json)}"
            },
            address: routable!(uri)
          )

          return true if response.is_a?(Net::HTTPSuccess)

          raise Refused, "#{name} answered #{response.code}"
        rescue *Outbound::UNREADABLE, URI::InvalidURIError => e
          raise Refused, "#{name} could not be reached: #{e.class}"
        end

        def routable!(uri)
          return if ::Rails.env.local?

          Outbound.vetted(uri) || raise(Refused, "#{name} resolves to an address this server will not call")
        end

        def issue_secret
          self.secret ||= SecureRandom.hex(32)
        end

        def url_is_callable
          problem = Outbound.problem_with(url)

          errors.add(:url, problem) if problem
        end

        def actions_are_known
          unknown = actions - Event::ACTIONS

          errors.add(:actions, "include unknown actions: #{unknown.join(', ')}") if unknown.any?
        end
    end
  end
end
