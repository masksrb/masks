module Masks
  module Server
    class Tenant < ApplicationRecord
      class TenancyConflict < StandardError
        def initialize(message = "MASKS_TENANT and MASKS_TENANTS are both set; declare one or the other")
          super
        end
      end

      class Exposed < StandardError
        def initialize(role)
          super(
            "this server connects to Postgres as #{role || 'a role it cannot read back'}, which sees " \
            "through row-level security. Every tenant_isolation policy on the database is decorative " \
            "while it does, and the only thing left between one tenant and another's actors, tokens " \
            "and signing keys is a default scope in Ruby. Connect as a role holding neither SUPERUSER " \
            "nor BYPASSRLS."
          )
        end
      end

      class Owner < StandardError
        def initialize(role)
          super(
            "this server connects to Postgres as #{role}, which owns the tables row-level security " \
            "protects. An owner can switch that protection off with one ALTER TABLE, so a single SQL " \
            "injection would read every tenant. Migrate as a separate role named by " \
            "MASKS_MIGRATION_USER and MASKS_MIGRATION_PASSWORD, and serve as a role that holds only " \
            "the grants bin/rails masks:grants hands it."
          )
        end
      end

      class Pooled < StandardError
        def initialize(message = nil)
          super(
            message ||
            "this server reaches Postgres through a pooler that hands out a different server " \
            "connection for each transaction. The tenant masks sets on one connection is gone from " \
            "the next, so a query would see no tenant's rows, or another tenant's. Connect masks to " \
            "Postgres directly, or run the pooler in session mode."
          )
        end
      end

      POOL_PROBE = "masks.pool_probe".freeze
      POOL_PROBE_ROUNDS = 3

      encrypts :pairwise_salt, :setup_token, key_provider: Server.tenant_key_provider

      attribute :uuid, default: -> { SecureRandom.uuid }

      store_accessor :settings, :ldap_enabled, :ldap_password_only

      has_many :signing_keys, dependent: :destroy
      has_many :actors, dependent: :destroy
      has_many :clients, dependent: :destroy
      has_many :tokens, dependent: :destroy
      has_many :sessions, dependent: :destroy
      has_many :consents, dependent: :destroy
      has_many :events, dependent: :delete_all
      has_many :senders, dependent: :destroy
      has_many :event_streams, dependent: :destroy
      has_many :organizations, dependent: :destroy
      has_many :domain_claims, dependent: :destroy
      has_many :sign_in_policies, dependent: :destroy
      belongs_to :sign_in_policy, optional: true

      NICKNAME = "nickname".freeze
      EMAIL = "email".freeze
      EITHER = "either".freeze
      ACCENT = /\A#\h{6}\z/
      NAMES = [ NICKNAME, EMAIL, EITHER ].freeze

      REGISTRATION_OFF = "off".freeze
      REGISTRATION_ANYTHING = "anything".freeze
      REGISTRATION_BOUNDED = "bounded".freeze
      REGISTRATIONS = [ REGISTRATION_OFF, REGISTRATION_ANYTHING, REGISTRATION_BOUNDED ].freeze

      IDLE_DAYS = (60..3650)
      RETENTION_DAYS = (30..2555)
      LINK_LIFETIMES = {
        invitation_lifetime: (1.hour.to_i..30.days.to_i),
        organization_invitation_lifetime: (1.hour.to_i..30.days.to_i),
        password_reset_lifetime: (5.minutes.to_i..1.day.to_i),
        email_verification_lifetime: (1.hour.to_i..14.days.to_i)
      }.freeze

      validates :named_by, inclusion: { in: NAMES }, allow_nil: true
      validates :accent_color, format: { with: ACCENT }, allow_nil: true
      validates :key_rotation_days, numericality: { only_integer: true, in: 7..365 }, allow_nil: true
      validates :dynamic_registration, inclusion: { in: REGISTRATIONS }, allow_nil: true
      validates :suspend_after, :delete_after, numericality: { only_integer: true, in: IDLE_DAYS }, allow_nil: true
      validates :event_retention_days, numericality: { only_integer: true, in: RETENTION_DAYS }, allow_nil: true
      def self.spoken(seconds)
        unit, length = { "day" => 1.day, "hour" => 1.hour, "minute" => 1.minute }.find { |_, held| (seconds % held).zero? }
        count = seconds / length

        "#{count} #{unit.pluralize(count)}"
      end

      LINK_LIFETIMES.each do |name, range|
        shortest, longest = [ range.begin, range.end ].map { |seconds| spoken(seconds) }

        validates name, numericality: { only_integer: true, in: range, message: "must be from #{shortest} to #{longest}" }
      end
      validates :delete_after, comparison: { greater_than: :suspend_after, message: "must be longer than suspend after" },
                               if: -> { suspend_after && delete_after }

      after_update_commit :forget_idle_warnings, if: -> { saved_change_to_suspend_after? || saved_change_to_delete_after? }
      validates :subdomain, presence: true, uniqueness: true,
                            format: { with: /\A[a-z0-9][a-z0-9-]*\z/ }
      validates :name, presence: true
      validates :custom_host, uniqueness: true, allow_nil: true,
                              format: { with: DomainClaim::HOSTNAME, message: "is not a host name" }
      validate :custom_host_is_proven, if: -> { custom_host.present? && will_save_change_to_custom_host? }

      normalizes :accent_color, with: ->(value) { value.to_s.strip.downcase.presence }
      normalizes :custom_host, with: ->(value) { value.to_s.strip.downcase.delete_suffix(".").presence }

      scope :active, -> { where(archived_at: nil) }
      scope :ldap, -> { active.where("settings->>'ldap_enabled' = 'true'") }
      scope :idling, -> { where.not(suspend_after: nil).or(where.not(delete_after: nil)) }

      before_create { self.keys_derived_at ||= Time.current }
      after_create_commit :ensure_signing_key!, :setup_token!

      def ldap?
        ActiveModel::Type::Boolean.new.cast(ldap_enabled) || false
      end

      def ldap_password_only?
        ActiveModel::Type::Boolean.new.cast(ldap_password_only) || false
      end

      def event_retention
        event_retention_days&.days || Event::RETENTION
      end

      def self.link_lifetime(name, tenant = Current.tenant)
        (tenant ? tenant[name] : column_defaults.fetch(name.to_s)).seconds
      end

      def self.default_link_lifetime(name)
        column_defaults.fetch(name.to_s)
      end

      def public_origin
        custom_origin || templated_origin || held_origin
      end

      def held_origin
        pinned_origin if self.class.pins_origin?
      end

      def templated_origin
        template = ::Rails.configuration.masks.public_origin_template

        template && format(template, subdomain: subdomain).chomp("/")
      end

      def custom_origin
        "https://#{custom_host}" if custom_host
      end

      def unserve_uncovered!(reason)
        return if custom_host.blank?

        if self.class.own_domain?(custom_host)
          reason = "inside this server's own domain"
        elsif covering_claim
          return
        end

        host = custom_host
        update_columns(custom_host: nil)
        Event.record!(Event::CUSTOM_DOMAIN_STOPPED, by: nil, host: host, reason: reason)
      end

      def covering_claim
        return nil if custom_host.blank?

        domain_claims.verified.find { |claim| custom_host == claim.domain || custom_host.end_with?(".#{claim.domain}") }
      end

      def named_by
        self.class.pinned_names.presence || super.presence || EITHER
      end

      def names_pinned?
        self.class.pinned_names.present?
      end

      def browsers_only
        pinned = ::Rails.configuration.masks.browsers_only

        pinned.nil? ? super : ActiveModel::Type::Boolean.new.cast(pinned)
      end

      def browsers_pinned?
        ::Rails.configuration.masks.browsers_only.present?
      end

      def blocked_agents
        ::Rails.configuration.masks.blocked_agents.presence || super
      end

      def agents_pinned?
        ::Rails.configuration.masks.blocked_agents.present?
      end

      def agent_list
        blocked_agents.to_s.split(/[\r\n,]+/).map { |one| one.strip.downcase }.reject(&:empty?)
      end

      def refuses?(user_agent)
        return true if browsers_only && !Device.browser?(user_agent)

        held = user_agent.to_s.downcase

        held.present? && agent_list.any? { |pattern| held.include?(pattern) }
      end

      def sender(kind)
        Tenant.switch(self) { Sender.primary(kind) }
      end

      def mail_sender
        sender(Sender::MAIL)
      end

      def sms_sender
        sender(Sender::SMS)
      end

      def mail_from
        mail_sender&.from || ::Rails.configuration.masks.mail_from
      end

      def mails?
        return true if mail_sender

        ::Rails.configuration.masks.mail_from.present? && ActionMailer::Base.smtp_settings.present?
      end

      def texts?
        sms_sender.present?
      end

      def dynamic_registration
        self.class.pinned_registration.presence || super.presence || registration_unset
      end

      def registration_pinned?
        self.class.pinned_registration.present?
      end

      def registers?
        dynamic_registration != REGISTRATION_OFF
      end

      def registration_unset
        held = dynamic_client_scopes.presence || ::Rails.configuration.masks.dynamic_client_scopes

        held.present? ? REGISTRATION_BOUNDED : REGISTRATION_ANYTHING
      end

      def dynamic_client_ceiling
        return nil unless dynamic_registration == REGISTRATION_BOUNDED

        declared = dynamic_client_scopes.presence ||
          ::Rails.configuration.masks.dynamic_client_scopes

        Scopes.list(declared.presence || Scopes.join(Scopes::STANDARD))
      end

      class << self
        def pinned
          ::Rails.configuration.masks.tenant
        end

        def pinned_names
          ::Rails.configuration.masks.named_by
        end

        def pinned_registration
          ::Rails.configuration.masks.dynamic_registration
        end

        def resolve(host)
          serving(host) || named(host)
        end

        def pins_origin?
          ::Rails.configuration.masks.public_origin_template.nil? && ::Rails.configuration.masks.pin_origin
        end

        def served_domain
          template = ::Rails.configuration.masks.public_origin_template

          return nil if template.nil?

          host = URI.parse(format(template, subdomain: "tenant")).host.to_s

          template.include?("%{subdomain}") ? host.split(".", 2).last : host
        end

        def own_domain?(host)
          served = served_domain

          served.present? && (host == served || host.to_s.end_with?(".#{served}"))
        end

        def serving(host)
          held = host.to_s.downcase

          active.find_by(custom_host: held) if held.present?
        end

        def named(host)
          return active.find_by(subdomain: pinned) if pinned

          active.find_by(subdomain: host.to_s.split(".").first)
        end

        def declared
          return ::Rails.configuration.masks.tenants unless pinned
          raise TenancyConflict if ::Rails.configuration.masks.tenants.any?

          [ pinned ]
        end

        def declare!
          declared.map do |subdomain|
            active.find_by(subdomain: subdomain) || create!(subdomain: subdomain, name: subdomain)
          end
        end

        def wildcard?
          template = ::Rails.configuration.masks.public_origin_template

          template.present? && template.include?("%{subdomain}")
        end

        def claiming?
          declared.none? && (wildcard? || !exists?)
        end

        def claim(host)
          return nil unless claiming?

          subdomain = host.to_s.split(".").first

          create!(subdomain: subdomain, name: subdomain)
        rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
          nil
        end

        def isolated!
          return true if @isolated

          held = role_privileges

          raise Exposed, held&.fetch("rolname", nil) unless held && held["bypasses"] == false
          raise Owner, held["rolname"] if held["owns"] && guards_ownership?
          raise Pooled if pooled?

          @isolated = true
        end

        def pooled?
          return false if connection_pool.size < 2

          POOL_PROBE_ROUNDS.times do
            mine = SecureRandom.hex(8)
            connection.exec_query("SELECT set_config($1, $2, false)", "probe", [ POOL_PROBE, mine ])

            return false unless touched_another_connection?

            return true unless connection.select_value("SELECT current_setting('#{POOL_PROBE}', true)") == mine
          end

          false
        rescue ActiveRecord::ConnectionTimeoutError
          false
        end

        def role_privileges
          connection.select_one(<<~SQL)
            SELECT rolname, rolsuper OR rolbypassrls AS bypasses,
                   EXISTS (SELECT 1 FROM pg_class WHERE relrowsecurity AND relowner = pg_roles.oid) AS owns
            FROM pg_roles WHERE rolname = current_user
          SQL
        end

        def guards_ownership?
          !::Rails.env.local? && !Server.engine?
        end

        def switch(tenant)
          raise ArgumentError, "no tenant" if tenant.nil?

          isolated!

          return yield tenant if Current.tenant&.id == tenant.id

          held = Current.tenant

          enter(tenant)

          begin
            yield tenant
          ensure
            enter(held)
          end
        end

        def clear!
          enter(nil, for_transaction: false)
        end

        private

          def enter(tenant, for_transaction: connection.transaction_open?)
            Current.tenant = tenant

            connection.exec_query(
              "SELECT set_config($1, $2, $3)", "tenant",
              [ TenantIsolation::SETTING, tenant&.id.to_s, for_transaction ]
            )

            connection.clear_query_cache
          rescue ActiveRecord::ConnectionNotEstablished, ActiveRecord::ConnectionFailed
            nil
          end

          def touched_another_connection?
            other = connection_pool.checkout

            return false if other.equal?(connection)

            other.exec_query("SELECT set_config($1, $2, false)", "probe", [ POOL_PROBE, "another connection" ])
            true
          ensure
            connection_pool.checkin(other) if other
          end
      end

      def signing_key
        Tenant.switch(self) { signing_keys.active.first } || ensure_signing_key!
      end

      def save(**options, &block) = keyed { super }

      def save!(**options, &block) = keyed { super }

      def update_columns(attributes) = keyed { super }

      def encrypt = keyed { super }

      def decrypt = keyed { super }

      def attributes = keyed { super }

      def _read_attribute(name, &block) = keyed { super }

      def pairwise_salt!
        return pairwise_salt if pairwise_salt.present?

        with_lock { update!(pairwise_salt: SecureRandom.hex(32)) if pairwise_salt.blank? }

        pairwise_salt
      end

      def set_up?
        Tenant.switch(self) { Actor.exists? }
      end

      def setup_token!
        ::Rails.configuration.masks.setup_token || minted_setup_token
      end

      def set_up!
        self.setup_token = nil
        self.pinned_origin ||= Current.origin.presence if self.class.pins_origin?

        save! if changed?
      end

      def setup_announcement
        return "#{subdomain} is not set up. Its setup token is the one MASKS_SETUP_TOKEN holds." if ::Rails.configuration.masks.setup_token.present?

        "#{subdomain} is not set up. Its setup token is #{setup_token!}"
      end

      def ensure_signing_key!
        Tenant.switch(self) do
          signing_keys.active.first || SigningKey.generate!(tenant: self)
        end
      end

      def to_identity
        { "uuid" => uuid, "subdomain" => subdomain, "name" => name }
      end

      def logo_url(size: 64)
        "#{Current.origin}#{Engine.routes.url_helpers.tenant_logo_path(v: logo_digest, size: size)}" if logo_digest.present?
      end

      def accent
        accent_color if accent_color.to_s.match?(ACCENT)
      end

      def accent_ink
        return nil if accent.nil?

        red, green, blue = accent_color.delete("#").scan(/../).map { |pair| pair.to_i(16) / 255.0 }
        light = [ red, green, blue ].map { |part| part <= 0.03928 ? part / 12.92 : ((part + 0.055) / 1.055)**2.4 }
        luminance = (0.2126 * light[0]) + (0.7152 * light[1]) + (0.0722 * light[2])

        luminance > 0.179 ? "#000000" : "#ffffff"
      end

      private

        def keyed(&) = TenantKeyProvider.keyed(self, &)

        def custom_host_is_proven
          if self.class.own_domain?(custom_host)
            errors.add(:custom_host, "is part of this server's own domain")
          elsif covering_claim.nil?
            errors.add(:custom_host, "must be within a domain this tenant has proven")
          end
        end

        def forget_idle_warnings
          Tenant.switch(self) do
            Actor.where.not(idle_warned_at: nil).update_all(idle_warned_at: nil)
          end
        end

        def minted_setup_token
          return setup_token if setup_token.present?

          minted = with_lock do
            next false if setup_token.present?

            update!(setup_token: SecureRandom.base58(32))
          end

          ::Rails.logger.warn("masks: #{setup_announcement}") if minted

          setup_token
        end
    end
  end
end
