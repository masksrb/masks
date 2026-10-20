module Masks
  module Server
    class AppPassword < Token
      ALPHABET = "abcdefghjkmnpqrstuvwxyz23456789".freeze
      LENGTH = 24
      GROUP = 4
      LIFETIME = 100.years
      NAME_LIMIT = 64
      MOST = 20
      USED_GRAIN = 1.minute

      class Refused < StandardError; end

      scope :newest_first, -> { order(created_at: :desc) }

      class << self
        def offered(actor)
          Client.active.where(app_passwords: true).order(:name).select { |client| client.admits?(actor) }
        end

        def issue!(actor:, client:, name:)
          label = name.to_s.strip

          raise Refused, "name" if label.empty? || label.length > NAME_LIMIT
          raise Refused, "app" if client.nil? || offered(actor).none? { |offered| offered.id == client.id }
          raise Refused, "too_many" if live.where(actor: actor).count >= MOST

          secret = Array.new(LENGTH) { ALPHABET[SecureRandom.random_number(ALPHABET.length)] }.join
          held = create!(actor: actor, client: client, digest: BCrypt::Password.create(secret, cost: cost),
                         payload: { "name" => label }, expires_at: LIFETIME.from_now)
          held.instance_variable_set(:@secret, grouped(secret))
          held
        end

        def normalize(secret)
          secret.to_s.downcase.delete("- ")
        end

        def shaped?(secret)
          offered = normalize(secret)

          offered.length == LENGTH && offered.each_char.all? { |char| ALPHABET.include?(char) }
        end

        def check(actor:, client:, secret:)
          offered = normalize(secret)
          return burn(offered) unless actor && client && shaped?(offered)

          found = live.where(actor: actor, client: client).to_a.find { |held| BCrypt::Password.new(held.digest) == offered }

          found || burn(offered)
        end

        def grouped(secret)
          secret.scan(/.{1,#{GROUP}}/o).join("-")
        end

        private

          def cost
            ActiveModel::SecurePassword.min_cost ? BCrypt::Engine::MIN_COST : BCrypt::Engine.cost
          end

          def burn(secret)
            BCrypt::Password.new(Actor.decoy_digest) == secret
            nil
          end
      end

      def name
        held("name")
      end

      def used_at
        held("used_at")&.then { |value| Time.zone.parse(value) }
      end

      def used!
        return if used_at && used_at > USED_GRAIN.ago

        now = Time.current
        today = now.to_date.iso8601
        first_today = held("used_on") != today

        update_columns(payload: (payload || {}).merge("used_at" => now.iso8601, "used_on" => today))

        Event.record!(Event::APP_PASSWORD_USED, actor: actor, client: client, name: name) if first_today
      end
    end
  end
end
