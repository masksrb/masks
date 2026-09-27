module Masks
  module Server
    class Session < ApplicationRecord
      include TenantScoped

      LIFETIME = 14.days
      FRESHNESS = 15.minutes
      SEEN_EVERY = 1.minute

      belongs_to :actor
      belongs_to :device, optional: true

      scope :unexpired, -> { where(revoked_at: nil).where("expires_at > ?", Time.current) }
      scope :live, -> {
        unexpired.where(
          "idle_timeout IS NULL OR last_seen_at IS NULL OR last_seen_at + make_interval(secs => idle_timeout) > ?",
          Time.current
        )
      }

      attr_reader :secret, :seen_before

      class << self
        def start!(actor:, device: nil, user_agent: nil, ip_address: nil, amr: [], origin: nil, policy: nil)
          secret = SecureRandom.urlsafe_base64(48)
          lifetime = policy&.session_lifetime&.seconds || LIFETIME
          now = Time.current

          session = create!(
            actor: actor,
            device: device,
            device_version: device&.version,
            digest: Digest::SHA256.hexdigest(secret),
            user_agent: user_agent,
            ip_address: ip_address,
            origin: origin.presence || Current.origin,
            authenticated_at: now,
            last_seen_at: now,
            amr: Array(amr),
            expires_at: now + lifetime,
            idle_timeout: policy&.session_idle_timeout,
            bounded: policy.present? && policy.bounds_sessions?
          )

          session.instance_variable_set(:@secret, secret)
          actor.active!
          session
        end

        def resume(secret)
          return nil if secret.blank?

          session = unexpired.includes(:device).find_by(digest: Digest::SHA256.hexdigest(secret.to_s))

          return nil unless session&.bound?

          if session.idle?
            session.expire!
            return nil
          end

          session.seen!
        end
      end

      def bound?
        device.nil? || device.carries?(self)
      end

      def relying_parties
        Client
          .where(id: Token.where(session_id: id).select(:client_id))
          .where.not(backchannel_logout_uri: [ nil, "" ])
          .distinct
      end

      def idle?(now = Time.current)
        idle_timeout.present? && last_seen_at.present? && last_seen_at <= now - idle_timeout.seconds
      end

      def idle_for(now = Time.current)
        now - (seen_before || last_seen_at || authenticated_at)
      end

      def seen!(now = Time.current)
        @seen_before = last_seen_at

        update_columns(last_seen_at: now) if last_seen_at.nil? || last_seen_at <= now - SEEN_EVERY

        self
      end

      def live?(now = Time.current)
        revoked_at.nil? && expires_at > now && !idle?(now)
      end

      def expire!
        return true if revoked_at.present?

        revoke!
        Event.record!(Event::SESSION_EXPIRED, actor: actor, by: nil, device: device, reason: "idle")

        true
      end

      def fresh?
        authenticated_at.present? && authenticated_at > FRESHNESS.ago
      end

      def revoke!
        return true if revoked_at.present?

        update!(revoked_at: Time.current)
        BackchannelLogout.announce(self)

        true
      end
    end
  end
end
