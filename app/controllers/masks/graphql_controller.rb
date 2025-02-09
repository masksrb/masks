module Masks
  class GraphqlController < ApplicationController
    include Masks::Controller

    managers_only optional: true

    def execute
      variables = prepare_variables(params[:variables])
      query = params[:query]
      operation_name = params[:operationName]
      context = {
        device: current_device,
        actor: current_actor,
        manager: current_actor&.masks_manager?,
        show_secrets: request.headers["x-show-secrets"],
      }

      result =
        MasksSchema.execute(
          query,
          variables: variables,
          context: context,
          operation_name: operation_name,
        )
      render json: result
    rescue StandardError => e
      raise e unless Rails.env.development?
      handle_error_in_development(e)
    end

    private

    # Handle variables in form data, JSON body, or a blank value
    def prepare_variables(variables_param)
      case variables_param
      when String
        variables_param.present? ? JSON.parse(variables_param) || {} : {}
      when Hash
        variables_param
      when ActionController::Parameters
        variables_param.to_unsafe_hash # GraphQL-Ruby will validate name and type of incoming variables.
      when nil
        {}
      else
        raise ArgumentError, "Unexpected parameter: #{variables_param}"
      end
    end

    def handle_error_in_development(e)
      logger.error e.message
      logger.error e.backtrace.join("\n")

      render json: {
               errors: [{ message: e.message, backtrace: e.backtrace }],
               data: {
               },
             },
             status: 500
    end
  end
end
