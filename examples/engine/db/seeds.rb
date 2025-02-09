Masks.seed do
  # Set up a default client for the demo...
  client "demo",
         name: "try out masks",
         type: "internal",
         scopes: {
           required: "demo",
         }

  # Set up a few actors with varying levels of access...
  # Note: a manager is seeded from config/actors.yml, for exemplary purposes
  actor "demo", password: "password", scopes: ["demo"], manager: true
  actor "developer", password: "password", scopes: %w[demo local]
  actor "limited", password: "password"
end
