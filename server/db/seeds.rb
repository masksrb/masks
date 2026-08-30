TENANTS = [
  { subdomain: "jons", name: "Jon's Dev Env" },
  { subdomain: "acme", name: "Acme Dev Env" }
].freeze

TENANTS.each do |attributes|
  tenant = Tenant.find_or_initialize_by(subdomain: attributes[:subdomain])
  tenant.name = attributes[:name]
  tenant.save!

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
