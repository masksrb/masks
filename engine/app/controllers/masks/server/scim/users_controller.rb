module Masks
  module Server
    module Scim
      class UsersController < ApplicationController
        include ScimEndpoint

        def index
          relation = Scim::Filter.apply(directory.people, params[:filter], columns: directory.columns)
          start, count = scim_page
          actors = relation.order(:created_at, :id).offset(start - 1).limit(count).to_a

          scim(listed(actors.map { |actor| represent(directory.user(actor)) }, total: relation.count(:all), start: start))
        end

        def show
          user = directory.user(found)

          response.headers["ETag"] = user.version
          scim(represent(user))
        end

        def create
          user = settle!(directory.user(Actor.new).replace(document), Event::ACTOR_PROVISIONED)

          response.headers["Location"] = "#{scim_base}/Users/#{user.actor.uuid}"
          scim(represent(user), status: :created)
        end

        def replace
          user = changeable

          scim(represent(settle!(user.replace(document), Event::ACTOR_UPDATED)))
        end

        def update
          user = changeable
          patch_document!

          scim(represent(settle!(user.patch(document["Operations"]), Event::ACTOR_UPDATED)))
        end

        def destroy
          directory.remove!(found)

          head :no_content
        end

        private

          def found
            directory.people.find_by(uuid: params[:id].to_s.match?(Subjects::UUID) ? params[:id] : nil) ||
              raise(Scim::Error.new(:not_found, "no user has that id"))
          end

          def changeable
            user = directory.user(found)

            matched!(user)
            directory.owned!(user.actor)

            user
          end

          def represent(user)
            user.to_h(base: scim_base)
          end

          def matched!(user)
            wanted = request.headers["If-Match"].presence

            return if wanted.nil? || wanted == "*" || wanted == user.version

            raise Scim::Error.new(:precondition_failed, "that user has changed since it was read")
          end

          def settle!(user, action)
            actor = user.actor

            directory.proven!(actor) if actor.email_changed?
            guarded!(actor)
            directory.keep_a_manager!(actor) if user.suspending && !actor.suspended?

            actor.email_verified_at = actor.email.present? ? Time.current : nil if actor.email_changed?

            Actor.transaction do
              directory.save!(actor, user.external_id)
              suspend_or_restore!(actor, user.suspending)
            end

            Event.record!(action, actor: actor, by: nil, via: "scim", external_id: user.external_id)

            user
          rescue ActiveRecord::RecordInvalid => e
            raise taken if e.record.errors.details.values.flatten.any? { |detail| detail[:error] == :taken }

            raise Scim::Error.new(:bad_request, e.record.errors.full_messages.join("; "), scim_type: "invalidValue")
          rescue ActiveRecord::RecordNotUnique
            raise taken
          end

          def taken
            Scim::Error.new(:conflict, "another user already holds that userName, email or externalId", scim_type: "uniqueness")
          end

          def suspend_or_restore!(actor, suspending)
            return if suspending.nil?

            if suspending && !actor.suspended?
              actor.suspend!(reason: Actor::SCIM)
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
      end
    end
  end
end
