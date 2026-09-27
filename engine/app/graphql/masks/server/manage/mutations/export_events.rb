module Masks
  module Server
    module Manage
      module Mutations
        class ExportEvents < BaseMutation
          requires :read

          description "Prepares a download of every event in a range as newline-delimited JSON, one event per line " \
                      "in the shape event streams send. The link works for ten minutes, in a browser signed in as the " \
                      "manager who asked for it."

          argument :from, GraphQL::Types::ISO8601DateTime
          argument :to, GraphQL::Types::ISO8601DateTime
          argument :action, String, required: false
          argument :organization, ID, required: false
          argument :actor, ID, required: false

          field :url, String, null: false
          field :count, Integer, null: false
          field :expires_at, GraphQL::Types::ISO8601DateTime, null: false

          def resolve(from:, to:, **filters)
            export = Masks::Server::EventExport.new(from: from, to: to, by: viewer.uuid, filters: filters).validate!
            count = export.scope.count

            audit!(Masks::Server::Event::EVENTS_EXPORTED, from: from.iso8601, to: to.iso8601, count: count,
                                                         **export.filters.transform_keys(&:to_sym).except(:organization))

            {
              url: "#{Current.origin}/manage/exports/#{ERB::Util.url_encode(export.secret(Current.tenant))}",
              count: count,
              expires_at: Masks::Server::EventExport::LIFETIME.from_now
            }
          rescue Masks::Server::EventExport::Refused => e
            refuse!(e.message)
          end
        end
      end
    end
  end
end
