module Masks
  module Server
    module Scim
      class User
        SIMPLE = {
          "externalId" => :external_id,
          "displayName" => :name,
          "profileUrl" => :profile_url,
          "locale" => :locale,
          "timezone" => :zoneinfo,
          "name.givenName" => :given_name,
          "name.familyName" => :family_name,
          "name.middleName" => :middle_name,
          "name.formatted" => :name
        }.freeze

        attr_reader :actor, :suspending

        def self.represent(actor, base:)
          new(actor).to_h(base: base)
        end

        def initialize(actor)
          @actor = actor
        end

        def to_h(base:)
          {
            "schemas" => [ USER ],
            "id" => actor.uuid,
            "externalId" => actor.external_id,
            "userName" => actor.nickname || actor.email,
            "name" => {
              "formatted" => actor.name,
              "givenName" => actor.given_name,
              "familyName" => actor.family_name,
              "middleName" => actor.middle_name
            }.compact.presence,
            "displayName" => actor.name,
            "profileUrl" => actor.profile_url,
            "locale" => actor.locale,
            "timezone" => actor.zoneinfo,
            "active" => !actor.suspended?,
            "emails" => ([ { "value" => actor.email, "type" => "work", "primary" => true } ] if actor.email),
            "phoneNumbers" => ([ { "value" => actor.phone, "type" => "mobile" } ] if actor.phone),
            "photos" => ([ { "value" => actor.picture_url, "type" => "photo" } ] if actor.picture_url),
            "meta" => {
              "resourceType" => "User",
              "created" => actor.created_at&.iso8601,
              "lastModified" => actor.updated_at&.iso8601,
              "location" => "#{base}/Users/#{actor.uuid}",
              "version" => version
            }
          }.compact
        end

        def version
          %(W/"#{actor.updated_at.to_f}")
        end

        def replace(document)
          raise Error.new(:bad_request, "userName is required", scim_type: "invalidValue") if document.to_h["userName"].blank?

          SIMPLE.each_value { |column| actor.public_send(:"#{column}=", nil) }
          actor.phone = actor.picture_url = nil

          merge(document)
        end

        def merge(document)
          document.to_h.each { |key, value| assign(key.to_s, value) }
          self
        end

        def patch(operations)
          raise Error.new(:bad_request, "a PATCH carries Operations", scim_type: "invalidSyntax") unless operations.is_a?(Array)

          operations.each do |operation|
            op = operation["op"].to_s.downcase
            path = operation["path"].presence

            raise Error.new(:bad_request, "#{operation['op']} is not an operation", scim_type: "invalidSyntax") unless %w[add replace remove].include?(op)

            if op == "remove"
              raise Error.new(:bad_request, "remove needs a path", scim_type: "noTarget") if path.nil?

              assign(path, nil)
            elsif path
              assign(path, operation["value"])
            elsif operation["value"].is_a?(Hash)
              merge(operation["value"])
            else
              raise Error.new(:bad_request, "an operation without a path carries an object", scim_type: "invalidValue")
            end
          end

          self
        end

        private

          def assign(path, value)
            key = path.sub(/\A#{Regexp.escape(USER)}:/o, "")

            case key
            when "userName" then user_name!(value)
            when "active" then active!(value)
            when "name" then value.is_a?(Hash) ? value.each { |part, held| assign("name.#{part}", held) } : clear_name
            when "password" then actor.password = value.presence
            when /\Aemails(\[.*\])?(\.value)?\z/ then actor.email = first_value(value)
            when /\AphoneNumbers(\[.*\])?(\.value)?\z/ then actor.phone = first_value(value)
            when /\Aphotos(\[.*\])?(\.value)?\z/ then actor.picture_url = first_value(value)
            else
              column = SIMPLE[key]
              actor.public_send(:"#{column}=", value.is_a?(String) || value.nil? ? value : value.to_s) if column
            end
          end

          def user_name!(value)
            raise Error.new(:bad_request, "userName is required", scim_type: "invalidValue") if value.blank?

            held = value.to_s.strip

            if held.match?(URI::MailTo::EMAIL_REGEXP)
              actor.email = held
              actor.nickname = nil if actor.nickname&.casecmp?(held)
            else
              actor.nickname = held
            end
          end

          def active!(value)
            active = ActiveModel::Type::Boolean.new.cast(value.is_a?(String) ? value.downcase : value)

            @suspending = !active
          end

          def clear_name
            actor.name = actor.given_name = actor.family_name = actor.middle_name = nil
          end

          def first_value(value)
            return value&.to_s&.strip.presence unless value.is_a?(Array)

            chosen = value.find { |entry| entry.is_a?(Hash) && entry["primary"] } || value.first
            chosen.is_a?(Hash) ? chosen["value"]&.to_s&.strip.presence : chosen&.to_s&.strip.presence
          end
      end
    end
  end
end
