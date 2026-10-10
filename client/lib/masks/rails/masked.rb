module Masks
  module Rails
    class Masked
      attr_reader :claims, :scopes, :access_token, :expires_at, :account_url

      def self.nobody(config)
        new(claims: Masks::Client::Claims.new({}), scopes: [], config: config, signed_in: false)
      end

      def initialize(claims:, scopes:, config:, signed_in:, access_token: nil, expires_at: nil, account_url: nil)
        @claims = claims
        @scopes = Array(scopes).map(&:to_s).freeze
        @config = config
        @signed_in = signed_in
        @access_token = access_token
        @expires_at = expires_at
        @account_url = account_url
      end

      def signed_in?
        @signed_in
      end

      def [](claim)
        claims[claim]
      end

      def subject
        claims.subject
      end

      def name
        claims["name"]
      end

      def nickname
        claims["preferred_username"]
      end

      def email
        claims["email"]
      end

      def email_verified?
        claims["email_verified"] == true
      end

      def picture
        claims.picture
      end

      def avatars
        claims.avatars
      end

      def tenant
        claims.tenant
      end

      def organization
        held = claims.organization

        held.present? ? held : nil
      end

      def organizations
        claims.organizations
      end

      def role?(*roles)
        organization&.role?(*roles) || false
      end

      def permits?(scope)
        scopes.include?(scope.to_s)
      end

      def privileges
        return [] unless signed_in?

        @config.privileges.values.select { |privilege| holds?(privilege) }.map(&:name)
      end

      def privilege?(*names)
        wanted = names.flatten.map { |name| @config.privilege(name) }

        signed_in? && wanted.all? { |privilege| holds?(privilege) }
      end

      def holds?(privilege)
        return false unless (privilege.scopes - scopes).empty?

        member!(privilege)
        true
      rescue Masks::Client::Forbidden
        false
      end

      def member!(privilege)
        return if privilege.roles.empty? && privilege.organization.nil?

        claims.member!(*privilege.roles, organization: privilege.organization)
      end

      def to_h
        {
          "signed_in" => signed_in?,
          "subject" => subject,
          "name" => name,
          "nickname" => nickname,
          "email" => email,
          "email_verified" => claims["email_verified"],
          "picture" => picture,
          "avatars" => avatars.to_h.presence,
          "tenant" => claims["tenant"],
          "organization" => organization&.to_h,
          "organizations" => organizations.map(&:to_h).presence,
          "scopes" => scopes,
          "privileges" => privileges,
          "expires_at" => expires_at,
          "account_url" => account_url
        }.compact
      end
    end
  end
end
