module Masks
  module Server
    class EnrollmentToken < Token
      SHORTEST = 1.minute
      LONGEST = 1.hour

      class << self
        def lifetime
          15.minutes
        end

        def issue!(client, scope:, name: nil, expires_in: nil)
          scopes = Scopes.list(scope)
          refusal = client.enrollment_refusal(scopes)

          raise Client::EnrollmentRefused, refusal if refusal

          mint!(
            client: client,
            scopes: Scopes.join(scopes),
            audience: client.resources,
            payload: { "name" => name.to_s.strip.presence }.compact,
            expires_at: lasting(expires_in).from_now
          )
        end

        def redeem!(secret, metadata)
          transaction(requires_new: true) do
            token = claim(secret)

            next nil if token.nil?

            Client.enroll!(token, metadata)
          end
        end

        private

          def lasting(expires_in)
            return lifetime if expires_in.blank?

            seconds = Integer(expires_in.to_s, 10)

            raise ArgumentError unless seconds.between?(SHORTEST.to_i, LONGEST.to_i)

            seconds.seconds
          rescue ArgumentError
            raise Client::EnrollmentRefused,
                  "expires_in must be between #{SHORTEST.to_i} and #{LONGEST.to_i} seconds"
          end
      end
    end
  end
end
