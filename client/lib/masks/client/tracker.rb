module Masks
  module Client
    class Tracker
      TTL = 3600
      LIMIT = 5

      class Entry
        attr_reader :id, :data, :opened_at, :expires_at

        def self.from_h(id, held)
          return nil unless held.is_a?(Hash)

          new(
            id: id,
            data: held["data"] || {},
            opened_at: held["opened_at"].to_f,
            expires_at: held["expires_at"].to_f
          )
        end

        def initialize(id:, data:, opened_at:, expires_at:)
          @id = id
          @data = data
          @opened_at = opened_at
          @expires_at = expires_at
        end

        def live?(now = Time.now.to_f)
          expires_at > now
        end

        def [](key)
          data[key.to_s]
        end

        def to_h
          { "data" => data, "opened_at" => opened_at, "expires_at" => expires_at }
        end
      end

      attr_reader :store, :ttl, :limit

      def initialize(store, ttl: TTL, limit: LIMIT)
        @store = store
        @ttl = ttl
        @limit = limit
      end

      def open(**data)
        id = SecureRandom.urlsafe_base64(32)
        now = Time.now.to_f

        entry = Entry.new(
          id: id,
          data: data.transform_keys(&:to_s).compact,
          opened_at: now,
          expires_at: now + ttl
        )

        write(sweep.merge(id => entry.to_h))
        entry
      end

      def amend(id, **data)
        held = sweep
        entry = Entry.from_h(id, held[id])
        return nil if entry.nil?

        merged = Entry.new(
          id: id,
          data: entry.data.merge(data.transform_keys(&:to_s).compact),
          opened_at: entry.opened_at,
          expires_at: entry.expires_at
        )

        write(held.merge(id => merged.to_h))
        merged
      end

      def claim(id)
        return nil if id.nil? || id.empty?

        held = sweep
        entry = Entry.from_h(id, held[id])
        return nil if entry.nil? || !entry.live?

        write(held.except(id))
        entry
      end

      def clear!
        write({})
      end

      def size
        sweep.size
      end

      private

        def sweep
          now = Time.now.to_f

          held = read.select do |id, value|
            entry = Entry.from_h(id, value)
            entry&.live?(now)
          end

          held.to_a.last(limit).to_h
        end

        def read
          value = store.read
          value.is_a?(Hash) ? value : {}
        end

        def write(held)
          store.write(held)
        end
    end
  end
end
