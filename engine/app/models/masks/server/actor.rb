module Masks
  module Server
    class Actor < ApplicationRecord
      include TenantScoped
      include Paged

      EXTERNAL_ID = ->(value) { value.to_s.strip.presence }

      include Password
      include SecondFactors
      include Suspension
      include Notices
      include Claims

      has_many :tokens, dependent: :destroy
      has_many :sessions, dependent: :destroy
      has_many :consents, dependent: :destroy
      has_many :device_factors, dependent: :destroy
      has_many :passkeys, dependent: :destroy
      has_many :subjects, dependent: :destroy
      has_many :delegations, dependent: :destroy
      has_many :connections, dependent: :destroy
      has_many :memberships, dependent: :destroy
      has_many :organizations, -> { merge(Membership.accepted) }, through: :memberships
      has_many :approvals, class_name: "Client", foreign_key: :approved_by_id, dependent: :nullify
      has_one :avatar, dependent: :destroy
      has_many :group_members, dependent: :delete_all
      has_many :access_requests, dependent: :delete_all
      has_many :groups, through: :group_members

      before_destroy :release_nickname

      attr_accessor :trusted_rename

      validates :nickname,
                uniqueness: { scope: :tenant_id, case_sensitive: false },
                format: { with: /\A[a-z0-9][a-z0-9._-]*\z/i },
                allow_blank: true
      validates :email,
                format: { with: URI::MailTo::EMAIL_REGEXP },
                uniqueness: { scope: :tenant_id, case_sensitive: false },
                allow_blank: true

      validates :external_id, uniqueness: { scope: :tenant_id }, allow_nil: true

      validates :phone,
                format: { with: Senders::Sms::NUMBER },
                uniqueness: { scope: :tenant_id },
                allow_blank: true

      validate :named
      validate :nickname_free, if: -> { nickname.present? && will_save_change_to_nickname? && !trusted_rename }

      after_save :release_previous_nickname, if: :saved_change_to_nickname?
      after_update :forget_mailed_links, if: :saved_change_to_email?
      after_commit :settle_sourced_groups, on: %i[create update], if: -> { saved_changes.keys.intersect?(Group::WATCHED) }

      normalizes :nickname, with: ->(value) { value.to_s.strip.presence }
      normalizes :email, with: ->(value) { value.to_s.strip.downcase.presence }
      normalizes :external_id, with: EXTERNAL_ID
      normalizes :phone, with: ->(value) { value.to_s.gsub(/[\s().-]/, "").presence }

      normalizes :name, :given_name, :family_name, :middle_name, :profile_url, :picture_url,
                 :website_url, :gender, :birthdate, :zoneinfo, :locale,
                 with: ->(value) { value.to_s.strip.presence }

      HOLDING = <<~SQL.squish.freeze
        EXISTS (
          SELECT 1 FROM regexp_split_to_table(actors.scopes, '[\\s,]+') AS entry
          WHERE entry <> ''
            AND (
              entry = :held
              OR (
                right(entry, 1) = ':'
                AND starts_with(:held, entry)
                AND length(:held) > length(entry)
              )
            )
        )
        OR (btrim(actors.scopes) = '' AND :held = ANY(ARRAY[:standard]))
      SQL

      scope :directed, -> { where.not(external_id: nil).or(where(id: Membership.where.not(external_id: nil).select(:actor_id))) }
      scope :holding, ->(held) { where(HOLDING, held: held.to_s.strip, standard: Scopes::STANDARD) }

      class << self
        def locate(identifier)
          wanted = identifier.to_s.strip
          return nil if wanted.blank?

          find_by(nickname: wanted) || find_by(email: wanted.downcase)
        end

        def invite!(email:, nickname: nil, scopes: nil)
          create!(
            nickname: nickname,
            email: email,
            scopes: Scopes.join(Scopes.list(scopes).presence || Scopes::STANDARD)
          )
        end
      end

      def devices
        Device.for_actor(self)
      end

      def scope_list
        list = Scopes.list(scopes)

        list.empty? ? Scopes::STANDARD.dup : list
      end

      def permitted_scopes(requested)
        Scopes.union(Scopes.granted(Scopes.list(requested), scope_list), Scopes.delegable(requested),
                     Scopes.list(requested) & Scopes::EVERYONE)
      end

      def holds?(scope)
        scope_list.include?(scope.to_s)
      end

      def grant!(requested)
        wanted = Scopes.list(requested) - scope_list
        return scope_list if wanted.empty?

        update!(scopes: Scopes.join(scope_list + wanted))

        scope_list
      end

      def withheld(requested)
        Scopes.list(requested) - permitted_scopes(requested)
      end

      def identifier
        nickname.presence || email
      end

      def handle
        "@#{nickname}" if nickname.present?
      end

      def display_name
        name.presence || handle || email
      end

      def display_details
        [ handle, email.presence ].compact - [ display_name ]
      end

      def email_unconfirmed?
        email.present? && email_verified_at.nil?
      end

      def verify_email!(address)
        return false if email_verified_at.present? || !email.to_s.casecmp?(address.to_s)

        update!(email_verified_at: Time.current)
        Event.record!(Event::EMAIL_VERIFIED, actor: self)

        true
      end

      def manages?
        ManageRoles.any?(scope_list)
      end

      def owns?
        holds?(Scopes::MANAGE)
      end

      def card_json
        style = Avatars.held?(self) ? Avatars::PHOTO : Avatars::FALLBACK

        {
          "name" => display_name,
          "details" => display_details,
          "note" => (I18n.t("application.actor.unconfirmed") if email_unconfirmed?),
          "role" => (I18n.t("application.actor.manager") if manages?),
          "avatar" => Avatars.url(self, style, subject: uuid, size: 128)
        }
      end

      private

        def settle_sourced_groups
          Group.ruled.find_each { |group| group.settle!(self) }
        end

        def forget_mailed_links
          [ PasswordReset, Invitation, EmailVerification ].each do |kind|
            kind.where(actor_id: id).live.find_each(&:consume!)
          end
        end

        def named
          return manages_by_both if manages?

          case tenant&.named_by
          when Tenant::NICKNAME then errors.add(:nickname, :blank) if nickname.blank?
          when Tenant::EMAIL then errors.add(:email, :blank) if email.blank?
          else errors.add(:base, :unnamed) if nickname.blank? && email.blank?
          end
        end

        def nickname_free
          errors.add(:nickname, :held) if ReleasedNickname.held_from?(nickname, self)
        end

        def release_previous_nickname
          ReleasedNickname.where(nickname: nickname.to_s.downcase, actor_id: id).delete_all if nickname.present?
          ReleasedNickname.release!(nickname_before_last_save, actor: self)
        end

        def release_nickname
          ReleasedNickname.release!(nickname, actor: self)
        end

        def manages_by_both
          errors.add(:nickname, :blank) if nickname.blank?
          errors.add(:email, :blank) if email.blank?
        end
    end
  end
end
