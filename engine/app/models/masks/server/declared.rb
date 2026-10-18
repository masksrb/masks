module Masks
  module Server
    class Declared
      class Invalid < StandardError; end

      TENANT_KEYS = %w[name accent_color groups apps].freeze
      APP_KEYS = %w[preset url slug name client_id client_secret_env redirect_uris scopes allowed_groups
                    access_token_lifetime refresh_token_lifetime refresh_token_absolute_lifetime].freeze

      def self.apply!(path = ::Rails.configuration.masks.config_path)
        return [] if path.blank?

        new(YAML.safe_load_file(path, aliases: false) || {}).apply!
      rescue Errno::ENOENT
        raise Invalid, "MASKS_CONFIG names #{path}, which does not exist"
      rescue Psych::Exception => e
        raise Invalid, "#{path} is not YAML masks can read: #{e.message}"
      end

      def initialize(document)
        raise Invalid, "the declared configuration must be a mapping" unless document.is_a?(Hash)

        @document = document
      end

      def apply!
        tenants.flat_map do |tenant, declared|
          Tenant.switch(tenant) { apply_tenant(tenant, declared) }
        end
      end

      private

        def tenants
          if @document.key?("tenants")
            @document.fetch("tenants").map do |subdomain, declared|
              [ Tenant.active.find_by(subdomain: subdomain) || raise(Invalid, "no tenant called #{subdomain}"), declared || {} ]
            end
          else
            served = Tenant.active.to_a
            raise Invalid, "name each tenant under tenants: when this server serves more than one" unless served.one?

            [ [ served.first, @document ] ]
          end
        end

        def apply_tenant(tenant, declared)
          known!(declared, TENANT_KEYS, tenant.subdomain)

          tenant.update!(declared.slice("name", "accent_color").compact) if declared.key?("name") || declared.key?("accent_color")

          Array(declared["groups"]).each { |key, group| apply_group(key, group || {}) }
          Array(declared["apps"]).filter_map { |key, app| apply_app(tenant, key, app || {}) }
        end

        def apply_group(key, declared)
          group = Group.find_or_initialize_by(key: key)
          group.update!(name: declared["name"] || group.name || key.to_s.humanize)

          Array(declared["members"]).each do |identifier|
            actor = Actor.locate(identifier) || raise(Invalid, "group #{key} names #{identifier}, who has no account")
            group.add!(actor)
          end
        end

        def apply_app(tenant, key, declared)
          known!(declared, APP_KEYS, "app #{key}")

          preset = declared["preset"] && (AppPreset.find(declared["preset"]) || raise(Invalid, "app #{key} names no preset called #{declared['preset']}"))
          client = Client.find_or_initialize_by(client_id: (declared["client_id"] || key).to_s)
          created = client.new_record?

          client.assign_attributes(described(preset, key, declared).merge(dynamic: false, approved_at: client.approved_at || Time.current))
          secret = secret_for(client, declared)
          client.save!

          Event.record!(created ? Event::CLIENT_CREATED : Event::CLIENT_UPDATED, client: client, name: client.name, declared: true)

          "#{tenant.subdomain}: #{client.name} has the client secret #{secret}. It is not shown again." if secret
        rescue ActiveRecord::RecordInvalid, AppPreset::Unusable => e
          raise Invalid, "app #{key}: #{e.message}"
        end

        def described(preset, key, declared)
          url = declared["url"].to_s.strip.delete_suffix("/").presence

          held = {
            name: declared["name"] || preset&.name || key.to_s,
            client_uri: url,
            redirect_uris: declared["redirect_uris"] || (preset ? preset.redirect_uris(base: url, name: declared["slug"]) : []),
            allowed_scopes: Scopes.join(declared["scopes"] || preset&.scopes || %w[openid profile email]),
            allowed_groups: Array(declared["allowed_groups"]),
            access_token_lifetime: declared["access_token_lifetime"],
            refresh_token_lifetime: declared["refresh_token_lifetime"],
            refresh_token_absolute_lifetime: declared["refresh_token_absolute_lifetime"],
            consent_required: false
          }

          return held.merge(protocol: Client::FORWARD, grant_types: [], response_types: [], token_endpoint_auth_method: "none") if preset&.forward?

          held.merge(grant_types: %w[authorization_code refresh_token],
                     response_types: Client.response_types_for(%w[authorization_code]),
                     token_endpoint_auth_method: Client::DEFAULT_AUTH_METHOD)
        end

        def secret_for(client, declared)
          return nil unless client.secret?

          named = declared["client_secret_env"]

          if named
            value = ENV[named].presence || raise(Invalid, "#{named} holds no secret for #{client.client_id}")
            client.secret_digest = BCrypt::Password.create(value) unless client.authenticate_secret(value)
            return nil
          end

          client.issue_secret! if client.secret_digest.blank?
        end

        def known!(declared, keys, where)
          raise Invalid, "#{where} must be a mapping" unless declared.is_a?(Hash)

          unknown = declared.keys.map(&:to_s) - keys
          raise Invalid, "#{where} names #{unknown.join(', ')}, which masks does not read" if unknown.any?
        end
    end
  end
end
