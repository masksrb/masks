module Masks
  module Server
    module BreachedPasswords
      RANGE_URL = "https://api.pwnedpasswords.com/range/".freeze
      PREFIX = 5
      WITHIN = 3

      class << self
        def breached?(password)
          return false if password.blank?

          digest = Digest::SHA1.hexdigest(password.to_s).upcase
          prefix = digest[0, PREFIX]
          suffix = digest[PREFIX..]

          body = Outbound.fetch!(URI.parse("#{RANGE_URL}#{prefix}"), open: WITHIN, read: WITHIN, within: WITHIN)

          body.each_line.any? do |line|
            held, count = line.strip.split(":", 2)

            held.present? && ActiveSupport::SecurityUtils.secure_compare(held, suffix) && count.to_i.positive?
          end
        rescue Outbound::Refused, URI::InvalidURIError
          false
        end
      end
    end
  end
end
