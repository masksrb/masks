TENANTS = [
  { subdomain: "jons", name: "Jon's" },
  { subdomain: "acme", name: "Acme" }
].freeze

TENANTS.each do |attributes|
  tenant = Tenant.find_or_create_by!(subdomain: attributes[:subdomain]) do |record|
    record.name = attributes[:name]
  end

  Tenant.switch(tenant) do
    actor = Actor.find_or_initialize_by(nickname: "owner")
    actor.name = "#{attributes[:name]} owner"
    actor.email = "owner@#{attributes[:subdomain]}.invalid"
    actor.password = "password"
    actor.scopes = Scopes.join(Scopes::DESCRIBED.keys)
    actor.email_verified_at = Time.current
    actor.save!

    puts "#{tenant.subdomain}: #{actor.nickname} / password, key #{tenant.signing_key.kid}"
  end
end
