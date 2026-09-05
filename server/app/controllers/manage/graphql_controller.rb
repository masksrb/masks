module Manage
  class GraphqlController < ApplicationController
    include ManageEndpoint

    def execute
      with_manage_token do |token, actor|
        render json: ManageSchema.execute(
          document["query"],
          variables: document["variables"],
          operation_name: document["operationName"],
          context: { actor: actor, client: token.client, token: token }
        )
      end
    end

    private

      def document
        @document ||= uploaded? ? attached : sent
      end

      def sent
        {
          "query" => params[:query],
          "variables" => parse(params[:variables]),
          "operationName" => params[:operationName]
        }
      end

      def attached
        operation = parse(params[:operations])
        variables = parse(operation["variables"])

        parse(params[:map]).each do |part, paths|
          Array(paths).each { |path| place(variables, path, params[part]) }
        end

        operation.merge("variables" => variables)
      end

      def place(variables, path, file)
        keys = path.to_s.split(".")

        return unless keys.shift == "variables" && keys.any?

        held = keys[0..-2].inject(variables) { |inner, key| inner.is_a?(Hash) ? inner[key] : nil }

        held[keys.last] = file if held.is_a?(Hash)
      end

      def uploaded?
        params[:operations].present? && params[:map].present?
      end

      def parse(value)
        case value
        when String then JSON.parse(value.presence || "{}")
        when ActionController::Parameters then value.to_unsafe_h
        when Hash then value
        else {}
        end
      rescue JSON::ParserError
        {}
      end
  end
end
