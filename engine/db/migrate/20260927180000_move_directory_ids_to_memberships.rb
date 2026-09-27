class MoveDirectoryIdsToMemberships < ActiveRecord::Migration[8.1]
  include Masks::Server::TenantIsolation

  def up
    add_column :memberships, :external_id, :string
    add_index :memberships, %i[organization_id external_id], unique: true, where: "external_id IS NOT NULL"

    across_tenants(:memberships) do
      across_tenants(:actors) do
        execute <<~SQL
          UPDATE memberships
             SET external_id = actors.external_id
            FROM actors
           WHERE actors.id = memberships.actor_id
             AND actors.external_id IS NOT NULL
             AND memberships.provisioned
             AND NOT memberships.pending
             AND (SELECT count(*) FROM memberships held WHERE held.actor_id = actors.id AND held.provisioned) = 1
        SQL

        execute <<~SQL
          UPDATE actors
             SET external_id = NULL
           WHERE EXISTS (SELECT 1 FROM memberships WHERE memberships.actor_id = actors.id AND memberships.external_id IS NOT NULL)
        SQL
      end
    end
  end

  def down
    across_tenants(:memberships) do
      across_tenants(:actors) do
        execute <<~SQL
          UPDATE actors
             SET external_id = memberships.external_id
            FROM memberships
           WHERE memberships.actor_id = actors.id
             AND memberships.external_id IS NOT NULL
             AND actors.external_id IS NULL
        SQL
      end
    end

    remove_column :memberships, :external_id
  end
end
