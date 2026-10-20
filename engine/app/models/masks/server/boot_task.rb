require "socket"
require "zlib"

module Masks
  module Server
    class BootTask
      WINDOW = 10.minutes

      Outcome = Struct.new(:name, :host, :value, :done) do
        def done? = done
      end

      class << self
        def once(name, fingerprint: nil)
          key = "masks:boot:#{name}:#{Digest::SHA256.hexdigest(fingerprint.to_s)[0, 16]}"
          host = Socket.gethostname
          outcome = nil

          ActiveRecord::Base.transaction do
            ActiveRecord::Base.connection.execute("SELECT pg_advisory_xact_lock(#{lock_id(name)})")
            done_by = ::Rails.cache.read(key)

            if done_by
              outcome = Outcome.new(name, done_by, nil, false)
            else
              value = yield
              ::Rails.cache.write(key, host, expires_in: WINDOW)
              outcome = Outcome.new(name, host, value, true)
            end
          end

          outcome
        end

        def lock_id(name)
          Zlib.crc32("masks:boot:#{name}")
        end
      end
    end
  end
end
