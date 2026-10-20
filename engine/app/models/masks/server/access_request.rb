module Masks
  module Server
    class AccessRequest < ApplicationRecord
      include TenantScoped

      class Refused < StandardError; end

      LIFETIME = 30.days

      belongs_to :actor
      belongs_to :client
      belongs_to :decided_by, class_name: "Actor", optional: true

      scope :open, -> { where(granted_at: nil, declined_at: nil) }
      scope :lapsed, -> { where(created_at: ...LIFETIME.ago) }
      scope :newest_first, -> { order(created_at: :desc) }

      class << self
        def ask!(actor:, client:)
          return nil if client.admits?(actor)

          open.find_by(actor: actor, client: client) || begin
            created = create!(actor: actor, client: client)
            Event.record!(Event::ACCESS_REQUESTED, actor: actor, client: client)
            created
          end
        rescue ActiveRecord::RecordNotUnique
          open.find_by!(actor: actor, client: client)
        end

        def for_organization(organization)
          open.joins(:client).where("EXISTS (SELECT 1 FROM unnest(clients.allowed_groups) AS held WHERE held LIKE ?)",
                                   "#{sanitize_sql_like(organization.key)}:%")
        end
      end

      def open?
        granted_at.nil? && declined_at.nil?
      end

      def grant!(label: nil, by:, journey:)
        raise Refused, "#{actor.identifier} is already admitted to #{client.name}" if client.admits?(actor)
        raise Refused, "this request is already decided" unless open?

        chosen = label.presence || client.allowed_groups.first
        raise Refused, "#{chosen} is not one of the groups #{client.name} allows" unless client.allowed_groups.include?(chosen)

        transaction do
          admit!(chosen, by: by)
          update!(granted_at: Time.current, decided_by: by, label: chosen)
          Event.record!(Event::ACCESS_GRANTED, actor: actor, by: by, client: client, label: chosen)
        end

        ActorMailer.access_granted(self, journey: journey).deliver_later if actor.email.present?

        self
      end

      def decline!(by:, journey:)
        raise Refused, "this request is already decided" unless open?

        transaction do
          update!(declined_at: Time.current, decided_by: by)
          Event.record!(Event::ACCESS_DECLINED, actor: actor, by: by, client: client)
        end

        ActorMailer.access_declined(self, journey: journey).deliver_later if actor.email.present?

        self
      end

      def organization_roles
        client.allowed_groups.filter_map do |held|
          key, role = held.split(":", 2)
          [ key, role ] if role
        end
      end

      private

        def admit!(label, by:)
          key, role = label.split(":", 2)

          if role.nil?
            group = Group.find_by(key: key) || raise(Refused, "there is no group keyed #{key}")
            group.add!(actor, by: by)
          else
            organization = Organization.active.find_by(key: key) || raise(Refused, "there is no organization keyed #{key}")
            held = organization.memberships.find_by(actor: actor)
            held = held.destroy! && nil if held&.pending?

            if held.nil?
              Members.enroll!(organization, actor, role: role, by: by)
            elsif held.role != role
              Members.assign!(held, role: role, by: by)
            end
          end
        rescue Members::Refused => e
          raise Refused, e.message
        end
    end
  end
end
