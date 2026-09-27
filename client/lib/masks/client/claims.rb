module Masks
  module Client
    class Claims
      class Tenant
        attr_reader :to_h

        def initialize(hash)
          @to_h = hash.is_a?(Hash) ? hash : {}
        end

        def uuid
          to_h["uuid"]
        end

        def subdomain
          to_h["subdomain"]
        end

        def name
          to_h["name"]
        end

        def present?
          !uuid.nil? || !subdomain.nil?
        end

        def ==(other)
          other.is_a?(Tenant) ? to_h == other.to_h : false
        end
      end

      class Avatars
        STYLES = %w[photo identicon initials].freeze
        FALLBACK = "identicon".freeze

        attr_reader :to_h

        def initialize(hash)
          @to_h = hash.is_a?(Hash) ? hash : {}
        end

        STYLES.each do |style|
          define_method(style) { to_h[style] }
        end

        def [](style)
          to_h[style.to_s]
        end

        def photo?
          !photo.nil?
        end

        def present?
          to_h.any?
        end

        def ==(other)
          other.is_a?(Avatars) ? to_h == other.to_h : false
        end
      end

      class Organization
        OWNER = "owner".freeze

        attr_reader :to_h

        def initialize(hash)
          @to_h = hash.is_a?(Hash) ? hash.transform_keys(&:to_s) : {}
        end

        def id
          to_h["id"]
        end

        def key
          to_h["key"]
        end

        def name
          to_h["name"]
        end

        def role
          to_h["role"]
        end

        def role?(*roles)
          roles.flatten.map(&:to_s).include?(role)
        end

        def owner?
          role?(OWNER)
        end

        def present?
          !id.nil? && !key.nil? && !role.nil?
        end

        def ==(other)
          other.is_a?(Organization) ? to_h == other.to_h : false
        end
      end

      AVATARS = "masks:avatars".freeze
      ORGANIZATION = "org".freeze
      ORGANIZATIONS = "orgs".freeze

      attr_reader :to_h

      def initialize(claims)
        @to_h = claims
      end

      def [](name)
        to_h[name.to_s]
      end

      def subject
        self["sub"]
      end

      def issuer
        self["iss"]
      end

      def audience
        Array(self["aud"])
      end

      def client_id
        self["client_id"]
      end

      def jti
        self["jti"]
      end

      def act
        self["act"]
      end

      def tenant
        @tenant ||= Tenant.new(self["tenant"])
      end

      def avatars
        @avatars ||= Avatars.new(self[AVATARS])
      end

      def organization
        @organization ||= Organization.new(self[ORGANIZATION])
      end

      def organizations
        @organizations ||= Array(self[ORGANIZATIONS]).map { |held| Organization.new(held) }.select(&:present?).freeze
      end

      def member!(*roles, organization: nil)
        held = self.organization

        unless held.present?
          raise Forbidden.new("insufficient_organization", "this token names no organization",
                              scope: Session::ORGANIZATION)
        end

        if organization && held.key != organization.to_s && held.id != organization.to_s
          raise Forbidden.new("insufficient_organization", "this token was issued for #{held.key}, not #{organization}")
        end

        return held if roles.flatten.empty? || held.role?(*roles)

        raise Forbidden.new("insufficient_role", "#{held.role} in #{held.key} is not #{roles.flatten.join(' or ')}")
      end

      def picture
        self["picture"] || avatars.photo || avatars.identicon
      end

      def scopes
        @scopes ||= self["scope"].to_s.split(/\s+/).reject(&:empty?).freeze
      end

      def permits?(scope)
        scopes.include?(scope.to_s)
      end

      def permit!(scope)
        return true if permits?(scope)

        raise Forbidden.new(
          "insufficient_scope",
          "this token does not carry #{scope}",
          scope: scope.to_s
        )
      end

      def expires_at
        @expires_at ||= self["exp"] && Time.at(self["exp"])
      end

      def issued_at
        @issued_at ||= self["iat"] && Time.at(self["iat"])
      end

      def expired?(leeway: 0)
        return false if expires_at.nil?

        Time.now.to_i + leeway >= expires_at.to_i
      end
    end
  end
end
