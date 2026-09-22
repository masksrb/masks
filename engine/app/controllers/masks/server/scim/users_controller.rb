module Masks
  module Server
    module Scim
      class UsersController < ApplicationController
        include ScimEndpoint

        DEFAULT_COUNT = 100

        def index
          relation = Scim::Filter.apply(Actor.all, params[:filter])
          start = [ params[:startIndex].to_i, 1 ].max
          count = params[:count].present? ? params[:count].to_i.clamp(0, Scim::MAX_RESULTS) : DEFAULT_COUNT
          actors = relation.order(:created_at, :id).offset(start - 1).limit(count).to_a

          scim({
            "schemas" => [ Scim::LIST ],
            "totalResults" => relation.count,
            "startIndex" => start,
            "itemsPerPage" => actors.length,
            "Resources" => actors.map { |actor| represent(actor) }
          })
        end

        def show
          actor = found

          response.headers["ETag"] = Scim::User.new(actor).version
          scim(represent(actor))
        end

        def create
          actor = settle!(Scim::User.new(Actor.new).replace(document), Event::ACTOR_PROVISIONED)

          response.headers["Location"] = "#{scim_base}/Users/#{actor.uuid}"
          scim(represent(actor), status: :created)
        end

        def replace
          actor = found
          matched!(actor)

          settle!(Scim::User.new(actor).replace(document), Event::ACTOR_UPDATED)
          scim(represent(actor))
        end

        def update
          actor = found
          matched!(actor)

          unless Array(document["schemas"]).include?(Scim::PATCH)
            raise Scim::Error.new(:bad_request, "a PATCH names #{Scim::PATCH}", scim_type: "invalidSyntax")
          end

          settle!(Scim::User.new(actor).patch(document["Operations"]), Event::ACTOR_UPDATED)
          scim(represent(actor))
        end

        def destroy
          actor = found
          last_manager!(actor)

          held = { uuid: actor.uuid, identifier: actor.identifier, via: "scim" }

          actor.destroy!
          Event.record!(Event::ACTOR_DELETED, by: nil, **held)

          head :no_content
        end

        private

          def found
            Actor.find_by(uuid: params[:id].to_s.match?(Subjects::UUID) ? params[:id] : nil) ||
              raise(Scim::Error.new(:not_found, "no user has that id"))
          end

          def represent(actor)
            Scim::User.represent(actor, base: scim_base)
          end

          def matched!(actor)
            wanted = request.headers["If-Match"].presence

            return if wanted.nil? || wanted == "*" || wanted == Scim::User.new(actor).version

            raise Scim::Error.new(:precondition_failed, "that user has changed since it was read")
          end

          def settle!(user, action)
            actor = user.actor

            guarded!(actor)
            last_manager!(actor) if user.suspending && !actor.suspended?

            actor.email_verified_at = actor.email.present? ? Time.current : nil if actor.email_changed?

            Actor.transaction do
              actor.save!
              suspend_or_restore!(actor, user.suspending)
            end

            Event.record!(action, actor: actor, by: nil, via: "scim", external_id: actor.external_id)

            actor
          rescue ActiveRecord::RecordInvalid => e
            taken = e.record.errors.details.values.flatten.any? { |detail| detail[:error] == :taken }

            raise Scim::Error.new(taken ? :conflict : :bad_request, e.record.errors.full_messages.join("; "),
                                  scim_type: taken ? "uniqueness" : "invalidValue")
          rescue ActiveRecord::RecordNotUnique
            raise Scim::Error.new(:conflict, "another user already holds that userName, email or externalId", scim_type: "uniqueness")
          end

          def suspend_or_restore!(actor, suspending)
            return if suspending.nil?

            if suspending && !actor.suspended?
              actor.suspend!
              Event.record!(Event::ACTOR_SUSPENDED, actor: actor, by: nil, via: "scim")
            elsif !suspending && actor.suspended?
              actor.restore!
              Event.record!(Event::ACTOR_RESTORED, actor: actor, by: nil, via: "scim")
            end
          end

          def guarded!(actor)
            return if actor.new_record? || Scopes.reserved(actor.scope_list).empty?

            if actor.password_digest_changed? || actor.email_changed?
              raise Scim::Error.new(:forbidden, "#{actor.identifier} holds a masks: scope, so their password and email are not provisioned",
                                    scim_type: "mutability")
            end
          end

          def last_manager!(actor)
            return unless actor.last_manager?

            raise Scim::Error.new(:conflict, "#{actor.identifier} is the last person who manages masks here", scim_type: "mutability")
          end
      end
    end
  end
end
