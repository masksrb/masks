module Masks
  module Server
    module Replay
      def self.first?(kind, id, expires_in:, within: nil)
        key = [ kind, Current.tenant&.id, within, Digest::SHA256.hexdigest(id.to_s) ].compact.join(":")

        ::Rails.cache.write(key, true, expires_in: expires_in, unless_exist: true)
      end
    end
  end
end
