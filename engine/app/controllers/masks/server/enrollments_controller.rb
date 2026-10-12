module Masks
  module Server
    class EnrollmentsController < ApplicationController
      include TokenPresented

      rate_limit to: 30, within: 1.minute,
                 by: -> { [ current_tenant.id, request.remote_ip ].join(":") },
                 with: -> {
                   render json: {
                     "error" => "too_many_requests",
                     "error_description" => "too many enrollment tokens asked for from this address"
                   }, status: :too_many_requests
                 }

      before_action :no_store!

      def create
        client = authenticate_client!
        token = EnrollmentToken.issue!(client, scope: params[:scope], name: params[:client_name],
                                               expires_in: params[:expires_in])

        Event.record!(Event::CLIENT_ENROLLMENT_ISSUED, client: client, scopes: token.scopes,
                                                       name: token.held("name"), expires_at: token.expires_at.iso8601)

        render json: {
          "initial_access_token" => token.secret,
          "expires_in" => token.expires_in,
          "scope" => token.scopes
        }, status: :created
      rescue Client::EnrollmentRefused => e
        render json: { "error" => "invalid_request", "error_description" => e.message }, status: :bad_request
      end

      def destroy
        app = authenticate_client!
        machine = app.enrolled.find_by(client_id: params[:machine].to_s)

        return not_enrolled if machine.nil?

        revoked = machine.unenroll!

        Event.record!(Event::CLIENT_UNENROLLED, client: machine, name: machine.name, enrolled_by: app.client_id,
                                                  revoked: revoked)

        head :no_content
      end

      private

        def not_enrolled
          render json: {
            "error" => "invalid_request",
            "error_description" => "that client was not enrolled by this app"
          }, status: :not_found
        end
    end
  end
end
