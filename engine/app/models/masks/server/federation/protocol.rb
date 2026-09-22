module Masks
  module Server
    module Federation
      class Protocol
        STATE_BYTES = 32
        VERIFIER_BYTES = 64

        attr_reader :provider, :tokens

        def initialize(provider)
          @provider = provider
        end

        def start(callback:, delegated: false)
          handoff = {
            "state" => SecureRandom.urlsafe_base64(STATE_BYTES),
            "verifier" => SecureRandom.urlsafe_base64(VERIFIER_BYTES),
            "delegated" => delegated
          }.merge(extra_handoff)

          [ authorize_url(callback, handoff), handoff ]
        end

        def finish(params, handoff:, callback:)
          unless params["state"].present? &&
                 ActiveSupport::SecurityUtils.secure_compare(params["state"].to_s, handoff["state"].to_s)
            raise Provider::Untrusted, "the state did not match this browser"
          end

          raise Provider::Refused, upstream_error(params) if params["error"].present?
          raise Provider::Refused, "#{provider.name} returned no code" if params["code"].blank?

          @tokens = provider.redeem!(code: params["code"].to_s, redirect_uri: callback, verifier: handoff["verifier"])

          identity = normalize(identify(tokens, handoff, params)).merge(supplement(tokens)).compact

          raise Provider::Untrusted, "#{provider.name} returned no #{provider.subject_claim} to identify the account by" if identity["sub"].blank? && !anonymous?

          identity
        end

        private

          def extra_handoff
            {}
          end

          def anonymous?
            false
          end

          def supplement(_tokens)
            {}
          end

          def scopes
            provider.scope_list
          end

          def authorize_url(callback, handoff)
            delegated = handoff["delegated"]

            provider.authorize_url(
              redirect_uri: callback,
              state: handoff["state"],
              scopes: delegated ? Scopes.union(scopes, provider.delegated_scope_list) : scopes,
              nonce: handoff["nonce"],
              challenge: challenge(handoff["verifier"]),
              extra: delegated ? delegation_extra : {}
            )
          end

          def delegation_extra
            provider.delegation_params.is_a?(Hash) ? provider.delegation_params.stringify_keys : {}
          end

          def challenge(verifier)
            Base64.urlsafe_encode64(OpenSSL::Digest::SHA256.digest(verifier), padding: false)
          end

          def normalize(raw)
            map = provider.claim_map

            held = Provider::MAPPED_CLAIMS.index_with do |claim|
              map.key?(claim) ? dig(raw, map[claim]) : raw[claim]
            end

            held["sub"] = dig(raw, map["sub"])&.to_s.presence
            held.compact
          end

          def dig(raw, path)
            path.to_s.split(".").reduce(raw) do |held, part|
              case held
              when Hash then held[part]
              when Array then part.match?(/\A\d+\z/) ? held[part.to_i] : nil
              end
            end
          end

          def upstream_error(params)
            [ params["error"], params["error_description"] ].compact_blank.join(": ")
          end
      end
    end
  end
end
