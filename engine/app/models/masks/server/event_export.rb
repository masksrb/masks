module Masks
  module Server
    class EventExport
      class Refused < StandardError; end

      LIFETIME = 10.minutes
      LONGEST = 366.days
      CEILING = 250_000
      PURPOSE = "events/export".freeze
      FILTERS = %w[action organization actor].freeze

      attr_reader :from, :to, :filters

      class << self
        def verifier
          Server.message_verifier(PURPOSE)
        end

        def open(secret, tenant:)
          held = verifier.verified(secret.to_s, purpose: tenant.uuid)

          return nil unless held.is_a?(Hash)

          new(from: Time.zone.parse(held["from"]), to: Time.zone.parse(held["to"]), by: held["by"],
              filters: held["filters"] || {})
        end
      end

      def initialize(from:, to:, by:, filters: {})
        @from = from
        @to = to
        @by = by
        @filters = filters.to_h.stringify_keys.slice(*FILTERS).compact_blank
      end

      def validate!
        raise Refused, "from must come before to" if from.nil? || to.nil? || from >= to
        raise Refused, "an export covers at most #{LONGEST.in_days.round} days" if to - from > LONGEST
        raise Refused, "that range holds more than #{CEILING} events; narrow it" if scope.count > CEILING

        self
      end

      def secret(tenant)
        self.class.verifier.generate(
          { "from" => from.iso8601, "to" => to.iso8601, "by" => @by, "filters" => filters },
          expires_in: LIFETIME, purpose: tenant.uuid
        )
      end

      def exporter
        Actor.find_by(uuid: @by)
      end

      def scope
        held = Event.where(created_at: from...to)
        held = held.where(action: filters["action"]) if filters["action"]
        held = held.where(organization: Organization.find_by(key: filters["organization"])) if filters["organization"]
        held = held.where(actor: Actor.find_by(uuid: filters["actor"])) if filters["actor"]
        held
      end

      def lines(tenant)
        scope.includes(:actor, :by, :client, :organization).order(:created_at, :id).find_each(batch_size: 1_000)
             .map { |event| "#{event.exported(tenant).to_json}\n" }
      end

      def filename(tenant)
        "#{tenant.subdomain}-events-#{from.to_date.iso8601}-#{to.to_date.iso8601}.ndjson"
      end
    end
  end
end
