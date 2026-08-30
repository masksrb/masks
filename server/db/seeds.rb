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

    # A complete profile, because `profile` asks for thirteen claims and an
    # actor who has filled none of them releases none of them. The seeded owner
    # is what the conformance suite signs in as, so it carries the whole set.
    actor.given_name = attributes[:name]
    actor.family_name = "Owner"
    actor.middle_name = "Dev"
    actor.profile_url = "https://example.invalid/#{attributes[:subdomain]}/owner"
    actor.picture_url = "https://example.invalid/#{attributes[:subdomain]}/owner.png"
    actor.website_url = "https://example.invalid/#{attributes[:subdomain]}"
    actor.gender = "unspecified"
    actor.birthdate = "1970-01-01"
    actor.zoneinfo = "Etc/UTC"
    actor.locale = "en"
    actor.save!

    puts "#{tenant.subdomain}: #{actor.nickname} / password, key #{tenant.signing_key.kid}"
  end
end
