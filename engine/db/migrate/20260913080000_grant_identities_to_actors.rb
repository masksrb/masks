class GrantIdentitiesToActors < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      UPDATE actors
         SET scopes = btrim(scopes || ' identities')
       WHERE ' ' || scopes || ' ' LIKE '% openid %'
         AND ' ' || scopes || ' ' NOT LIKE '% identities %'
    SQL
  end

  def down
    execute "UPDATE actors SET scopes = btrim(regexp_replace(' ' || scopes || ' ', ' identities ', ' '))"
  end
end
