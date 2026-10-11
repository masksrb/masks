class RenameAdaptersToSenders < ActiveRecord::Migration[8.1]
  include Masks::Server::TenantIsolation

  def up
    rename_table :adapters, :senders
    rename_index :senders, "index_adapters_one_primary_per_kind", "index_senders_one_primary_per_kind"
    rename_actions "adapter.", "sender."
  end

  def down
    rename_actions "sender.", "adapter."
    rename_index :senders, "index_senders_one_primary_per_kind", "index_adapters_one_primary_per_kind"
    rename_table :senders, :adapters
  end

  private

    def rename_actions(from, to)
      across_tenants(:events) do
        execute <<~SQL
          UPDATE events
             SET action = #{quote(to)} || substr(action, #{from.length + 1})
           WHERE action LIKE #{quote("#{from}%")}
        SQL
      end

      across_tenants(:event_streams) do
        execute <<~SQL
          UPDATE event_streams
             SET actions = (
               SELECT jsonb_agg(
                        CASE WHEN value LIKE #{quote("#{from}%")}
                             THEN #{quote(to)} || substr(value, #{from.length + 1})
                             ELSE value END
                        ORDER BY ordinality)
                 FROM jsonb_array_elements_text(actions) WITH ORDINALITY
             )
           WHERE EXISTS (
             SELECT 1 FROM jsonb_array_elements_text(actions) AS held(value)
              WHERE held.value LIKE #{quote("#{from}%")}
           )
        SQL
      end
    end
end
