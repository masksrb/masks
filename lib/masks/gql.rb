require "graphql/client"
require "graphql/client/http"

module Masks
  # LOGIN_GQL = File.read(Pathname.new(__dir__).join('../../app/frontend/lib/entry.graphql'))

  class << self
    def gql
      @gql ||=
        if Masks.mode.server?
          raise "wtf"
        else
          Masks::Gql.new(url: Masks.conf.endpoint(:graphql))
        end
    end
  end

  class Gql
    attr_accessor :token

    def initialize(url:)
      @http =
        GraphQL::Client::HTTP.new(url) do
          def headers(context)
            # TODO
          end
        end
    end

    def client
      @client ||=
        begin
          GraphQL::Client.new(schema:, execute: @http)
        end
    end

    def login_gql
    end

    def schema_path
      # TODO
    end

    def schema
      @schema ||= GraphQL::Client.load_schema(schema_path)
    end

    def dump(path)
      GraphQL::Client.dump_schema(@http, schema_path)
    end
  end
end
