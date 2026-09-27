module Masks
  module Server
    class SignalStreamsController < ApplicationController
      include RackOAuth2Endpoint
      include ResourceToken

      class Invalid < StandardError; end
      class Missing < StandardError; end

      skip_forgery_protection

      rescue_from Invalid, ActiveRecord::RecordInvalid, ActionController::ParameterMissing do |error|
        message = error.respond_to?(:record) ? error.record.errors.full_messages.to_sentence : error.message

        render json: refusal(message), status: :bad_request
      end

      rescue_from Missing do
        render json: refusal("no stream with that stream_id"), status: :not_found
      end

      def configuration
        render json: issuer.signals_configuration
      end

      def show
        receiving do |client|
          stream = client_stream(client)

          next render(json: [ stream&.configuration ].compact) if params[:stream_id].blank?

          render json: stream!(stream).configuration
        end
      end

      def create
        receiving do |client|
          next render(json: refusal("this receiver already has a stream"), status: :conflict) if client_stream(client)

          stream = SignalStream.new(client: client, issuer: issuer.url, status: SignalStream::ENABLED)
          configure!(stream, replace: true)
          record!(Event::SIGNAL_STREAM_CREATED, stream)

          render json: stream.configuration, status: :created
        end
      end

      def update
        receiving do |client|
          stream = stream!(client_stream(client))
          configure!(stream, replace: request.put?)
          record!(Event::SIGNAL_STREAM_UPDATED, stream)

          render json: stream.configuration
        end
      end

      def destroy
        receiving do |client|
          stream = stream!(client_stream(client))
          stream.destroy!
          record!(Event::SIGNAL_STREAM_DELETED, stream)

          head :no_content
        end
      end

      def status
        receiving do |client|
          render json: stream!(client_stream(client)).state
        end
      end

      def update_status
        receiving do |client|
          stream = stream!(client_stream(client))
          status = body["status"].to_s

          raise Invalid, "status must be one of #{SignalStream::STATUSES.join(', ')}" unless SignalStream::STATUSES.include?(status)

          stream.update!(status: status, status_reason: body["reason"].to_s.truncate(255).presence)
          record!(Event::SIGNAL_STREAM_UPDATED, stream, status: status)

          render json: stream.state
        end
      end

      def verify
        receiving do |client|
          stream = stream!(client_stream(client))

          raise Invalid, "a disabled stream cannot be verified" if stream.status == SignalStream::DISABLED

          SignalJob.perform_later(stream.id, state: body["state"].to_s.truncate(255))

          head :no_content
        end
      end

      private

        def receiving
          with_access_token(scope: Scopes::SIGNALS) do |token|
            client = token.client

            if client.nil? || token.actor || client.public? || client.archived?
              next render(json: refusal("a receiver authenticates with its own client credentials"), status: :forbidden)
            end

            yield client
          end
        end

        def client_stream(client)
          SignalStream.find_by(client: client)
        end

        def stream!(stream)
          wanted = params[:stream_id].presence || body["stream_id"].presence

          raise Missing if stream.nil? || (wanted && wanted.to_s != stream.uuid)

          stream
        end

        def configure!(stream, replace:)
          delivery = body["delivery"]

          if replace || delivery
            raise Invalid, "delivery must name a method and an endpoint_url" unless delivery.is_a?(Hash)
            raise Invalid, "only push delivery (#{SignalStream::PUSH}) is supported" unless delivery["method"] == SignalStream::PUSH

            stream.endpoint_url = delivery["endpoint_url"].to_s
            stream.authorization_header = delivery["authorization_header"].to_s.presence
          end

          stream.events_requested = Array(body["events_requested"]) if replace || body.key?("events_requested")
          stream.description = body["description"].to_s.truncate(255).presence if replace || body.key?("description")
          stream.save!
        end

        def body
          @body ||= begin
            held = JSON.parse(request.raw_post.presence || "{}")
            raise Invalid, "the body must be a JSON object" unless held.is_a?(Hash)

            held
          rescue JSON::ParserError
            raise Invalid, "the body is not JSON"
          end
        end

        def refusal(message)
          { "error" => "invalid_request", "error_description" => message }
        end

        def record!(action, stream, **details)
          Event.record!(action, actor: nil, by: nil, client: stream.client, stream: stream.uuid, **details)
        end
    end
  end
end
