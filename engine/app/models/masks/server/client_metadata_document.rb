module Masks
  module Server
    class ClientMetadataDocument
      class Refused < StandardError; end

      CEILING = 5.kilobytes
      OPEN_TIMEOUT = 2
      READ_TIMEOUT = 3
      WITHIN = 5
      SHORTEST = 5.minutes
      LIFETIME = 1.hour
      LONGEST = 24.hours
      REFUSAL_LIFETIME = 5.minutes
      NAME_LIMIT = 100
      AUTH_METHODS = %w[none private_key_jwt].freeze
      DEFAULT_AUTH_METHOD = "none".freeze
      FORBIDDEN = %w[client_secret client_secret_expires_at registration_access_token registration_client_uri].freeze
      STRINGS = %w[client_name client_uri logo_uri tos_uri policy_uri jwks_uri backchannel_logout_uri
                   token_endpoint_auth_method application_type subject_type scope].freeze
      LISTS = %w[redirect_uris post_logout_redirect_uris grant_types response_types].freeze
      FLAGS = %w[backchannel_logout_session_required dpop_bound_access_tokens require_pushed_authorization_requests].freeze
      DESCRIPTIVE = %i[name client_uri logo_uri tos_uri policy_uri metadata_expires_at].freeze

      class << self
        def url?(client_id)
          problem_with(client_id).nil?
        end

        def problem_with(client_id)
          value = client_id.to_s
          uri = URI.parse(value)

          if !uri.is_a?(URI::HTTPS) && !(::Rails.env.local? && uri.is_a?(URI::HTTP))
            "must be an https URL"
          elsif value.length > Client::URI_LIMIT
            "must be at most #{Client::URI_LIMIT} characters"
          elsif uri.host.blank? || uri.userinfo.present? || uri.fragment
            "must name a host, and carry no credentials or fragment"
          elsif uri.path.blank? || uri.path == "/"
            "must have a path"
          elsif uri.path.split("/").intersect?(%w[. ..])
            "must not contain dot segments"
          end
        rescue URI::InvalidURIError
          "is not a URL"
        end

        def resolve(client_id)
          held = Client.find_by(client_id: client_id)

          return nil if held&.archived? || held&.protocol == SamlIdentity::PROTOCOL
          return held if held && !held.metadata_stale?
          return nil unless Current.tenant&.registers?

          new(client_id).save!(held)
        rescue Refused => e
          ::Rails.logger.info("masks: client metadata document #{client_id} refused: #{e.message}")
          nil
        end

        def refusal_key(client_id)
          "masks:client-metadata-document:#{Current.tenant&.id}:#{Digest::SHA256.hexdigest(client_id)}"
        end
      end

      attr_reader :client_id

      def initialize(client_id)
        @client_id = client_id
      end

      def save!(held)
        raise Refused, ::Rails.cache.read(refusal_key) if ::Rails.cache.exist?(refusal_key)

        document, expires_at = fetch
        client = held || Client.new(client_id: client_id, dynamic: true)
        created = client.new_record?

        client.assign_attributes(attributes(document, expires_at, approved: client.approved?))
        client.save!

        Event.record!(created ? Event::CLIENT_REGISTERED : Event::CLIENT_UPDATED,
                      client: client, name: client.name, dynamic: true, document: true)

        client
      rescue ActiveRecord::RecordNotUnique
        Client.find_by!(client_id: client_id)
      rescue ActiveRecord::RecordInvalid => e
        refuse!(e.record.errors.full_messages.join("; "))
      rescue Client::ScopesUnavailable, Outbound::Refused => e
        refuse!(e.message)
      end

      private

        def refusal_key
          self.class.refusal_key(client_id)
        end

        def refuse!(message)
          ::Rails.cache.write(refusal_key, message, expires_in: REFUSAL_LIFETIME)
          raise Refused, message
        end

        def fetch
          response = Outbound.get!(
            URI.parse(client_id),
            open: OPEN_TIMEOUT, read: READ_TIMEOUT, ceiling: CEILING, within: WITHIN,
            headers: { "Accept" => "application/json" }
          )

          [ checked(JSON.parse(response.body)), Time.current + lifetime(response["Cache-Control"]) ]
        rescue JSON::ParserError
          refuse!("is not JSON")
        end

        def checked(document)
          refuse!("is not a JSON object") unless document.is_a?(Hash)
          refuse!("names #{document['client_id'].to_s.truncate(80).inspect} as its client_id") unless document["client_id"] == client_id

          forbidden = FORBIDDEN & document.keys
          refuse!("must not carry #{forbidden.join(', ')}") if forbidden.any?

          STRINGS.each { |field| typed!(document, field, "a string", String) }
          FLAGS.each { |field| typed!(document, field, "true or false", TrueClass, FalseClass) }
          LISTS.each do |field|
            next if document[field].nil?

            refuse!("#{field} must be an array of strings") unless document[field].is_a?(Array) && document[field].all?(String)
          end
          typed!(document, "jwks", "an object", Hash)

          method = document["token_endpoint_auth_method"] || DEFAULT_AUTH_METHOD
          refuse!("token_endpoint_auth_method must be one of #{AUTH_METHODS.join(', ')}") unless AUTH_METHODS.include?(method)

          document
        end

        def typed!(document, field, expected, *types)
          value = document[field]
          return if value.nil? || types.any? { |type| value.is_a?(type) }

          refuse!("#{field} must be #{expected}")
        end

        def lifetime(cache_control)
          directives = cache_control.to_s.downcase.split(",").map(&:strip)

          return SHORTEST if directives.intersect?(%w[no-store no-cache])

          age = directives.filter_map { |directive| directive[/\Amax-age=(\d+)\z/, 1] }.first
          age ? Integer(age).seconds.clamp(SHORTEST, LONGEST) : LIFETIME
        end

        def attributes(document, expires_at, approved:)
          grant_types = Scopes.list(document["grant_types"]).presence || [ "authorization_code" ]

          described = {
            name: (document["client_name"].presence || URI.parse(client_id).host).truncate(NAME_LIMIT),
            client_uri: document["client_uri"],
            logo_uri: document["logo_uri"],
            tos_uri: document["tos_uri"],
            policy_uri: document["policy_uri"],
            metadata_expires_at: expires_at
          }

          return described if approved

          described.merge(
            redirect_uris: Array(document["redirect_uris"]),
            post_logout_redirect_uris: Array(document["post_logout_redirect_uris"]),
            grant_types: grant_types,
            response_types: Scopes.list(document["response_types"]).presence || Client.response_types_for(grant_types),
            allowed_scopes: Scopes.join(Client.bounded(document["scope"].presence || Client::DEFAULT_SCOPES)),
            token_endpoint_auth_method: document["token_endpoint_auth_method"] || DEFAULT_AUTH_METHOD,
            subject_type: document["subject_type"].presence || Subjects::PUBLIC,
            application_type: document["application_type"].presence || "web",
            jwks: document["jwks"],
            jwks_uri: document["jwks_uri"],
            backchannel_logout_uri: document["backchannel_logout_uri"],
            backchannel_logout_session_required: document["backchannel_logout_session_required"] || false,
            dpop_bound_access_tokens: document["dpop_bound_access_tokens"] || false,
            require_pushed_authorization_requests: document["require_pushed_authorization_requests"] || false
          )
        end
    end
  end
end
