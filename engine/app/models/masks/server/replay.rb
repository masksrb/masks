module Masks
  module Server
    class Replay < ApplicationRecord
      include TenantScoped

      class << self
        def first?(kind, id, expires_in:, within: nil)
          now = Time.current
          claimed = connection.exec_query(sanitize_sql_array([ <<~SQL, Current.tenant.id, kind.to_s, digest(within, id), now + expires_in, now, now ]), "Replay")
            INSERT INTO replays (tenant_id, kind, digest, expires_at, created_at)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT (tenant_id, kind, digest) DO UPDATE
              SET expires_at = EXCLUDED.expires_at, created_at = EXCLUDED.created_at
              WHERE replays.expires_at <= ?
            RETURNING id
          SQL

          claimed.rows.any?
        end

        private

          def digest(within, id)
            Digest::SHA256.hexdigest([ within&.to_s, id.to_s ].to_json)
          end
      end
    end
  end
end
