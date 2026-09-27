class GrantIdentitiesToActorsInEveryTenant < ActiveRecord::Migration[8.1]
  include Masks::Server::TenantIsolation

  def up
    across_tenants(:actors) do
      execute <<~SQL
        UPDATE actors
           SET scopes = btrim(scopes || ' identities')
         WHERE ' ' || scopes || ' ' LIKE '% openid %'
           AND ' ' || scopes || ' ' NOT LIKE '% identities %'
      SQL
    end
  end

  def down
  end
end
