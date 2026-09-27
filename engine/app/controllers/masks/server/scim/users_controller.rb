module Masks
  module Server
    module Scim
      class UsersController < ApplicationController
        include ScimEndpoint

        def index
          relation = Scim::Filter.apply(provisionable, params[:filter], columns: directory_columns)
          start, count = scim_page
          actors = relation.order(:created_at, :id).offset(start - 1).limit(count).to_a
          ids = directory_ids(actors)

          scim(listed(actors.map { |actor| represent(actor, ids.fetch(actor.id, actor.external_id)) }, total: relation.count, start: start))
        end

        def show
          actor = found

          response.headers["ETag"] = scim_user(actor).version
          scim(represent(actor))
        end

        def create
          actor = settle!(Scim::User.new(Actor.new, external_id: nil).replace(document), Event::ACTOR_PROVISIONED)

          response.headers["Location"] = "#{scim_base}/Users/#{actor.uuid}"
          scim(represent(actor), status: :created)
        end

        def replace
          actor = found
          matched!(actor)
          owned!(actor)

          settle!(scim_user(actor).replace(document), Event::ACTOR_UPDATED)
          scim(represent(actor))
        end

        def update
          actor = found
          matched!(actor)
          owned!(actor)
          patch_document!

          settle!(scim_user(actor).patch(document["Operations"]), Event::ACTOR_UPDATED)
          scim(represent(actor))
        end

        def destroy
          actor = found

          return leave!(actor) if provisioned_organization

          last_manager!(actor)

          held = { uuid: actor.uuid, identifier: actor.identifier, via: "scim" }

          actor.destroy!
          Event.record!(Event::ACTOR_DELETED, by: nil, **held)

          head :no_content
        end

        private

          def provisionable
            held = provisioned_organization

            held ? Actor.joins(:memberships).merge(held.memberships.accepted) : Actor.all
          end

          def directory_columns
            provisioned_organization ? { "externalid" => "memberships.external_id" } : {}
          end

          def directory_ids(actors)
            held = provisioned_organization

            return {} if held.nil?

            held.memberships.where(actor: actors).pluck(:actor_id, :external_id).to_h
          end

          def scim_user(actor)
            Scim::User.new(actor, external_id: directory_ids([ actor ]).fetch(actor.id, actor.external_id))
          end

          def found
            provisionable.find_by(uuid: params[:id].to_s.match?(Subjects::UUID) ? params[:id] : nil) ||
              raise(Scim::Error.new(:not_found, "no user has that id"))
          end

          def owned!(actor)
            held = provisioned_organization

            return if directory_owns?(actor)

            raise Scim::Error.new(:forbidden, "#{held.name}'s directory did not create #{actor.identifier}, or they belong " \
                                              "elsewhere too, so it can remove them but not change them", scim_type: "mutability")
          end

          def directed!(actor, external_id)
            held = provisioned_organization
            membership = held.memberships.find_by(actor: actor) ||
                         Members.enroll!(held, actor, role: Organization::MEMBER, by: nil, provisioned: true, via: "scim")

            return if membership.external_id == external_id

            membership.update!(external_id: external_id)
            actor.touch
          end

          def leave!(actor)
            held = provisioned_organization
            membership = held.memberships.find_by!(actor: actor)

            unless membership.destroy
              raise Scim::Error.new(:conflict, membership.errors.full_messages.to_sentence, scim_type: "mutability")
            end

            Token.live.where(organization: held, actor: actor).find_each(&:revoke!)
            Event.record!(Event::MEMBERSHIP_REMOVED, actor: actor, by: nil, organization: held.key, via: "scim")

            head :no_content
          end

          def represent(actor, external_id = scim_user(actor).external_id)
            Scim::User.represent(actor, base: scim_base, external_id: external_id)
          end

          def matched!(actor)
            wanted = request.headers["If-Match"].presence

            return if wanted.nil? || wanted == "*" || wanted == scim_user(actor).version

            raise Scim::Error.new(:precondition_failed, "that user has changed since it was read")
          end

          def settle!(user, action)
            actor = user.actor

            proven!(actor) if actor.email_changed?
            guarded!(actor)
            last_manager!(actor) if user.suspending && !actor.suspended?

            actor.email_verified_at = actor.email.present? ? Time.current : nil if actor.email_changed?

            actor.external_id = user.external_id unless provisioned_organization

            Actor.transaction do
              actor.save!
              suspend_or_restore!(actor, user.suspending)
              directed!(actor, user.external_id) if provisioned_organization
            end

            Event.record!(action, actor: actor, by: nil, via: "scim", external_id: user.external_id)

            actor
          rescue ActiveRecord::RecordInvalid => e
            raise taken if e.record.errors.details.values.flatten.any? { |detail| detail[:error] == :taken }

            raise Scim::Error.new(:bad_request, e.record.errors.full_messages.join("; "), scim_type: "invalidValue")
          rescue ActiveRecord::RecordNotUnique
            raise taken
          end

          def taken
            Scim::Error.new(:conflict, "another user already holds that userName, email or externalId", scim_type: "uniqueness")
          end

          def proven!(actor)
            held = provisioned_organization

            return if held.nil? || actor.email.blank?
            return if proven_domains(held).include?(actor.email.split("@", 2).last)

            raise Scim::Error.new(:bad_request, "#{held.name}'s directory sets only addresses at domains proven for #{held.name}",
                                  scim_type: "invalidValue")
          end

          def proven_domains(organization)
            @proven_domains ||= DomainClaim.verified.where(provider: organization.providers.active).order(:domain).pluck(:domain)
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

          def last_manager!(actor)
            return unless actor.last_manager?

            raise Scim::Error.new(:conflict, "#{actor.identifier} is the last person who manages masks here", scim_type: "mutability")
          end
      end
    end
  end
end
