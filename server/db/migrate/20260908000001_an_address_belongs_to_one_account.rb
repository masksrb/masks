class AnAddressBelongsToOneAccount < ActiveRecord::Migration[8.1]
  include TenantIsolation

  class Ambiguous < StandardError; end

  def up
    refuse!(shared) if shared.any?

    remove_index :actors, column: [ :tenant_id, :email ]
    add_index :actors, [ :tenant_id, :email ], unique: true
  end

  def down
    remove_index :actors, column: [ :tenant_id, :email ]
    add_index :actors, [ :tenant_id, :email ]
  end

  private

    def shared
      @shared ||= across_tenants(:actors) do
        select_rows(<<~SQL)
          SELECT t.subdomain, a.email, string_agg(a.nickname, ', ' ORDER BY a.nickname)
            FROM actors a
            JOIN tenants t ON t.id = a.tenant_id
           WHERE a.email IS NOT NULL
           GROUP BY t.subdomain, a.email
          HAVING count(*) > 1
           ORDER BY t.subdomain, a.email
        SQL
      end
    end

    def refuse!(rows)
      named = rows.map { |subdomain, email, nicknames| "  #{subdomain}: #{email} — #{nicknames}" }

      raise Ambiguous, <<~TEXT
        An address has to belong to one account before it can be relied on.

        These accounts share one, and until they do not, signing in by address,
        recovering a password and matching an upstream identity all resolve to
        whichever row the database happens to answer with:

        #{named.join("\n")}

        Give each account its own address, or clear the address from the ones
        that should not hold it, and run this migration again.
      TEXT
    end
end
