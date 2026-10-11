module Masks
  module Server
    module SamlIdentity
      class Farewells
        WAIT = 10.minutes

        attr_reader :finish

        def self.resume(request_id, client:)
          key = key_for(request_id)
          held = ::Rails.cache.read(key)

          return nil unless held.is_a?(Hash) && held["client_id"] == client.client_id

          ::Rails.cache.delete(key)
          new(held["steps"], held["finish"])
        end

        def self.key_for(request_id)
          [ "saml-farewell", Current.tenant&.id, Digest::SHA256.hexdigest(request_id.to_s) ].compact.join(":")
        end

        def initialize(steps, finish)
          @steps = Array(steps).dup
          @finish = finish
        end

        def advance(issuer)
          while (id = steps.shift)
            participation = SamlParticipation.listening.includes(:client).find_by(id: id)

            next if participation.nil?

            sign_off = participation.sign_off(issuer)
            ::Rails.cache.write(self.class.key_for(sign_off.id),
                                { "client_id" => participation.client.client_id, "steps" => steps, "finish" => finish },
                                expires_in: WAIT)

            return sign_off
          end

          nil
        end

        private

          attr_reader :steps
      end
    end
  end
end
