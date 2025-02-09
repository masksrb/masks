namespace :masks do
  namespace :doc do
    task graphql: :environment do
      require "graphql/rake_task"

      GraphQL::RakeTask.new(
        directory: "./doc/graphql",
        load_schema: ->(_task) do
          require "masks"

          Masks::MasksSchema
        end,
        # load_context: ->(_task) {
        #   { current_user: User.new(role: "admin") }
        # }
      )

      Rake::Task["graphql:schema:dump"].invoke
    end

    task settings: :environment do
      system "mkdir -p doc/settings"

      def generate(name, spec)
        puts "generating #{name}.json..."
        File.write("doc/settings/#{name}.json", JSON.pretty_generate(spec))
      end

      generate("masks", Masks::ConfCommand.new.settings_spec)
      generate("clients", Masks::ClientCommand.new.settings_spec)
      generate("providers", Masks::ProviderCommand.new.settings_spec)
      generate("actors", Masks::ActorCommand.new.settings_spec)
    end
  end

  # task :graphql_schema: :environment do
  #   GraphQL::RakeTask.new(
  #     load_schema: ->(_task) {
  #       require File.expand_path("../../config/environment", __dir__)
  #       MySchema
  #     },
  #     load_context: ->(_task) {kkkkkkkk
  #       { current_user: User.new(role: "admin") }
  #     }
  #   )
  # end
end
