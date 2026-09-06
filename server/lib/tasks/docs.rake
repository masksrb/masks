require_relative "../schema_reference"

namespace :docs do
  desc "Print the /manage GraphQL reference as an Astro page, for docs/"
  task schema: :environment do
    puts SchemaReference.new(ManageSchema).page
  end

  desc "Print the /manage schema as SDL, which the docs explorer reads"
  task sdl: :environment do
    puts ManageSchema.to_definition.strip
  end
end
