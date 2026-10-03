module Masks
  module Server
    class MailTemplate < ApplicationRecord
      include TenantScoped

      SIGNATURE = "signature".freeze
      KINDS = {
        "invitation" => %w[tenant name nickname organization],
        "organization_invitation" => %w[tenant name nickname organization role],
        "password_reset" => %w[tenant name nickname],
        "email_verification" => %w[tenant name nickname],
        "confirmation_code" => %w[tenant code],
        "approval_requested" => %w[tenant nickname],
        "approved" => %w[tenant name nickname],
        SIGNATURE => %w[tenant]
      }.freeze
      SUBJECT_LIMIT = 150
      MESSAGE_LIMIT = 2_000
      PLACEHOLDER = /\{\{\s*([a-z_]+)\s*\}\}/

      validates :kind, inclusion: { in: KINDS.keys }, uniqueness: { scope: :tenant_id }
      validates :subject, length: { maximum: SUBJECT_LIMIT }
      validates :message, length: { maximum: MESSAGE_LIMIT }
      validate :signature_has_no_subject
      validate :placeholders_are_known

      normalizes :subject, with: ->(value) { value.to_s.squish.presence }
      normalizes :message, with: ->(value) { value.to_s.gsub("\r\n", "\n").strip.presence }

      class << self
        def for(kind)
          find_by(kind: kind.to_s)
        end

        def each_kind
          held = all.index_by(&:kind)

          KINDS.keys.map { |kind| held[kind] || new(kind: kind) }
        end
      end

      def placeholders
        KINDS.fetch(kind, [])
      end

      def subject_for(values)
        subject && fill(subject, values).squish.presence
      end

      def paragraphs_for(values)
        return nil if message.blank?

        fill(message, values).split(/\n\s*\n/).map(&:strip).reject(&:empty?).presence
      end

      private

        def fill(text, values)
          text.gsub(PLACEHOLDER) { values.fetch(::Regexp.last_match(1).to_sym, "").to_s }
        end

        def signature_has_no_subject
          errors.add(:subject, "is not used by the signature") if kind == SIGNATURE && subject.present?
        end

        def placeholders_are_known
          [ subject, message ].compact.each do |text|
            unknown = text.scan(PLACEHOLDER).flatten.uniq - placeholders
            next if unknown.empty?

            errors.add(:base, "{{#{unknown.join('}}, {{')}}} is not offered here; use #{placeholders.map { |name| "{{#{name}}}" }.join(', ')}")
          end
        end
    end
  end
end
