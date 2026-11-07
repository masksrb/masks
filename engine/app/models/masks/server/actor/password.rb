module Masks
  module Server
    class Actor
      module Password
        extend ActiveSupport::Concern

        MINIMUM_PASSWORD = 8

        included do
          has_secure_password validations: false

          before_save :activate_once_a_password_exists
        end

        class_methods do
          def authenticate(identifier, password)
            actor = locate(identifier)

            return burn(password) if actor.nil? || actor.password_digest.blank? || !actor.activated?

            actor.authenticate(password.to_s) || nil
          end

          def decoy_digest
            @decoy_digest ||= BCrypt::Password.create(SecureRandom.hex(16))
          end

          private

            def burn(password)
              BCrypt::Password.new(decoy_digest) == password.to_s
              nil
            end
        end

        def password?
          password_digest.present?
        end

        def activated?
          activated_at.present?
        end

        def activate!(password, verifying_email: false)
          self.password = password
          self.email_verified_at = Time.current if verifying_email && email.present?
          save!
        end

        def reset_password!(password, verifying_email: false, keeping: nil)
          transaction do
            activate!(password, verifying_email: verifying_email)
            sign_out_everywhere!(keeping: keeping)
          end
        end

        def change_password!(current, password, keeping: nil)
          return false unless activated? && authenticate(current.to_s)

          reset_password!(password, keeping: keeping)
          true
        end

        def forget_unproven_ways_in!
          passkeys.find_each do |passkey|
            passkey.destroy!
            Event.record!(Event::PASSKEY_REMOVED, actor: self, passkey: passkey.name)
          end

          connections.destroy_all
        end

        def last_way_in?(passkey)
          !password? && !passkeys.where.not(id: passkey.id).exists? && !connections.live.exists?
        end

        private

          def activate_once_a_password_exists
            self.activated_at ||= Time.current if password_digest.present?
          end
      end
    end
  end
end
