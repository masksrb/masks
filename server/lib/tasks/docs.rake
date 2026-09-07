require_relative "../schema_reference"

namespace :docs do
  desc "Write the /manage reference page and the SDL the docs explorer reads"
  task reference: :environment do
    docs = File.expand_path("../../../docs", __dir__)

    File.open("#{docs}/src/content/docs/reference/manage.mdx", "w") do |page|
      page.puts SchemaReference.new(ManageSchema).page
    end

    File.open("#{docs}/src/assets/manage.graphql", "w") do |sdl|
      sdl.puts ManageSchema.to_definition.strip
    end
  end
end
