module Masks
  module Server
    class Actor
      module Claims
        extend ActiveSupport::Concern

        PROFILE_CLAIMS = {
          "name" => :name,
          "given_name" => :given_name,
          "family_name" => :family_name,
          "middle_name" => :middle_name,
          "nickname" => :nickname,
          "preferred_username" => :nickname,
          "profile" => :profile_url,
          "picture" => :picture_url,
          "website" => :website_url,
          "gender" => :gender,
          "birthdate" => :birthdate,
          "zoneinfo" => :zoneinfo,
          "locale" => :locale
        }.freeze

        AVATARS_CLAIM = "masks:avatars".freeze
        IDENTITIES_CLAIM = "identities".freeze
        ORGANIZATIONS_CLAIM = "orgs".freeze
        GROUPS_CLAIM = "groups".freeze

        def claims(scopes, subject:, requested: nil, origin: Current.origin)
          granted = Scopes.list(scopes)
          claims = { "sub" => subject, AVATARS_CLAIM => Avatars.urls(self, subject: subject, origin: origin) }

          if granted.include?(Scopes::PROFILE)
            PROFILE_CLAIMS.each_key { |claim| claims[claim] = claim_value(claim, origin, subject) }
            claims["updated_at"] = updated_at.to_i
          end

          if granted.include?(Scopes::EMAIL)
            claims["email"] = email
            claims["email_verified"] = email_verified_at.present?
          end

          claims[IDENTITIES_CLAIM] = identities if granted.include?(Scopes::IDENTITIES) && subject == uuid
          claims[ORGANIZATIONS_CLAIM] = organizations_held if granted.include?(Scopes::ORGANIZATION)
          claims[GROUPS_CLAIM] = group_labels if granted.include?(Scopes::GROUPS)

          asked(requested).each do |claim|
            claims[claim] = claim_value(claim, origin, subject) if PROFILE_CLAIMS.key?(claim)
          end

          claims.compact
        end

        def organizations_held
          memberships.live.map(&:claim)
        end

        def group_labels
          @group_labels ||= begin
            held = groups.pluck(:key)
            roles = memberships.live.joins(:organization).pluck("organizations.key", :role).map { |key, role| "#{key}:#{role}" }

            (held + roles).uniq.sort
          end
        end

        def identities
          connections.live.includes(:provider).order(:created_at).filter_map do |connection|
            next if connection.provider.archived?

            {
              "provider" => connection.provider.key,
              "protocol" => connection.provider.protocol,
              "sub" => connection.subject,
              "email" => (connection.email if connection.email_verified)
            }.compact
          end
        end

        private

          def claim_value(claim, origin, subject)
            return Avatars.picture(self, subject: subject, origin: origin) if claim == "picture"

            public_send(PROFILE_CLAIMS[claim])
          end

          def asked(requested)
            return [] if requested.blank?

            Array(requested["userinfo"]&.keys)
          end
      end
    end
  end
end
