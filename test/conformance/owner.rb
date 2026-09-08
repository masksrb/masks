Tenant.all.each do |tenant|
  Tenant.switch(tenant) do
    actor = Actor.find_or_initialize_by(nickname: ENV.fetch("OWNER", "owner"))

    actor.assign_attributes(
      name: "Conformance Owner",
      email: "owner@#{tenant.subdomain}.invalid",
      password: ENV.fetch("OWNER_PASSWORD", "password"),
      scopes: Scopes.join(Scopes::DESCRIBED.keys),
      email_verified_at: Time.current,
      given_name: "Conformance",
      family_name: "Owner",
      middle_name: "Suite",
      profile_url: "https://example.invalid/#{tenant.subdomain}/owner",
      picture_url: "https://example.invalid/#{tenant.subdomain}/owner.png",
      website_url: "https://example.invalid/#{tenant.subdomain}",
      gender: "unspecified",
      birthdate: "1970-01-01",
      zoneinfo: "Etc/UTC",
      locale: "en"
    )

    actor.save!

    puts "#{tenant.subdomain}: #{actor.nickname}"
  end
end
