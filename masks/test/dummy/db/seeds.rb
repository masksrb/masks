Masks.seed do
  client :default, name: "Dummy app", type: :internal
  client :masks, name: "Manage masks", type: :internal, required_scopes: ['masks:manage']
end
