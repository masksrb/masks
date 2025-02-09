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
        load_context: ->(_task) { { manager: true } },
      )

      Rake::Task["graphql:schema:dump"].invoke
    end
  end
end
