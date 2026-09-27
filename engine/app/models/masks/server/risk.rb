module Masks
  module Server
    class Risk
      WEIGHTS = {
        "new_device" => 30,
        "new_network" => 25,
        "risky_network" => 50,
        "failed_attempts" => 20,
        "many_failed_attempts" => 40,
        "dormant" => 10,
        "breached_password" => 40
      }.freeze

      MOST = 100
      LOOKBACK = 90.days
      DORMANT = 180.days
      FAILURES_WITHIN = 1.hour
      FEW_FAILURES = 3
      MANY_FAILURES = 10

      attr_reader :actor, :device, :ip_address, :breached

      def self.networks(value)
        value.to_s.split(/[\s,]+/).filter_map do |entry|
          IPAddr.new(entry)
        rescue IPAddr::InvalidAddressError, IPAddr::AddressFamilyError
          nil
        end
      end

      def initialize(actor:, device:, ip_address:, tenant: Current.tenant, breached: false)
        @actor = actor
        @device = device
        @ip_address = ip_address
        @tenant = tenant
        @breached = breached
      end

      def signals
        @signals ||= [
          ("new_device" if new_device?),
          ("new_network" if new_network?),
          ("risky_network" if risky_network?),
          failures,
          ("dormant" if dormant?),
          ("breached_password" if breached)
        ].compact
      end

      def score
        [ signals.sum { |signal| WEIGHTS.fetch(signal) }, MOST ].min
      end

      private

        def history
          @history ||= Session.where(actor: actor).where(created_at: LOOKBACK.ago..).to_a
        end

        def known?
          history.any?
        end

        def new_device?
          return false unless known?
          return true if device.nil?

          history.none? { |session| session.device_id == device.id } && !device.remembers?(actor, DeviceFactor::SECOND_FACTOR)
        end

        def new_network?
          return false unless known? && address

          history.none? { |session| (seen = parse(session.ip_address)) && network(seen).include?(seen) && network(address).include?(seen) }
        end

        def risky_network?
          address && self.class.networks(@tenant&.risky_networks).any? { |range| range.include?(address) }
        end

        def failures
          count = Event.where(action: Event::LOGIN_REFUSED, actor: actor, created_at: FAILURES_WITHIN.ago..).count

          if count >= MANY_FAILURES then "many_failed_attempts"
          elsif count >= FEW_FAILURES then "failed_attempts"
          end
        end

        def dormant?
          actor.last_login_at.present? && actor.last_login_at < DORMANT.ago
        end

        def address
          return @address if defined?(@address)

          @address = parse(ip_address)
        end

        def parse(value)
          value.present? ? IPAddr.new(value.to_s) : nil
        rescue IPAddr::InvalidAddressError, IPAddr::AddressFamilyError
          nil
        end

        def network(held)
          held.mask(held.ipv4? ? 24 : 48)
        end
    end
  end
end
