module Masks
  module Server
    module Ldap
      class Directory
        class NoSuchObject < StandardError
          attr_reader :matched

          def initialize(matched)
            @matched = matched
            super("no such entry")
          end
        end

        BASE = 0
        ONE = 1
        SUBTREE = 2
        SCOPES = [ BASE, ONE, SUBTREE ].freeze

        SUFFIX = "masks".freeze

        class << self
          def base_for(tenant)
            Dn.build([ :dc, tenant.subdomain ], [ :dc, SUFFIX ])
          end

          def tenant_for(dn)
            return nil if dn.depth < 2

            named, suffix = dn.rdns.last(2).map { |rdn| rdn.size == 1 && rdn.first.first == "dc" ? rdn.first.last.downcase : nil }
            return nil unless suffix == SUFFIX && named.present?

            Tenant.active.find_by(subdomain: named)
          end

          def uid_for(actor)
            actor.nickname.presence || actor.email
          end
        end

        attr_reader :tenant, :base

        def initialize(tenant)
          @tenant = tenant
          @base = self.class.base_for(tenant)
        end

        def people_dn
          base.child(:ou, "people")
        end

        def groups_dn
          base.child(:ou, "groups")
        end

        def services_dn
          base.child(:ou, "services")
        end

        def person_dn(actor)
          people_dn.child(:uid, self.class.uid_for(actor))
        end

        def group_dn(group)
          groups_dn.child(:cn, group.key)
        end

        def service_dn(label)
          services_dn.child(:cn, label)
        end

        def search(from, scope, uid: nil)
          raise NoSuchObject.new(nil) unless from.under?(base)

          uid = from.first_value if from.parent == people_dn && from.first_type == "uid"
          entries = containers
          entries += people(uid) if reaches?(people_dn, from, scope)
          entries += groups if reaches?(groups_dn, from, scope)

          raise NoSuchObject.new(matched(from, entries)) unless entries.any? { |entry| entry.dn == from }

          entries.select { |entry| within?(entry.dn, from, scope) }
        end

        def listed
          Actor.where(suspended_at: nil, pending_approval_at: nil).where.not(activated_at: nil)
        end

        private

          def containers
            [
              Entry.new(base, "objectClass" => %w[top dcObject organization], "dc" => tenant.subdomain, "o" => tenant.name),
              Entry.new(people_dn, "objectClass" => %w[top organizationalUnit], "ou" => "people"),
              Entry.new(groups_dn, "objectClass" => %w[top organizationalUnit], "ou" => "groups")
            ]
          end

          def people(uid)
            actors = listed
            if uid
              wanted = uid.to_s.downcase
              actors = actors.where("LOWER(nickname) = :uid OR (nickname IS NULL AND LOWER(email) = :uid)", uid: wanted)
            end

            actors = actors.order(:id).to_a
            joined = GroupMember.where(actor_id: actors.map(&:id)).pluck(:actor_id, :group_id).group_by(&:first)
            keys = Group.where(id: joined.values.flatten(1).map(&:last)).pluck(:id, :key).to_h

            actors.map { |actor| person(actor, joined.fetch(actor.id, []).filter_map { |_actor, group| keys[group] }) }
          end

          def person(actor, group_keys)
            uid = self.class.uid_for(actor)
            cn = actor.name.presence || uid

            Entry.new(
              person_dn(actor),
              "objectClass" => %w[top person organizationalPerson inetOrgPerson],
              "uid" => uid,
              "cn" => cn,
              "sn" => actor.family_name.presence || cn,
              "givenName" => actor.given_name,
              "displayName" => cn,
              "mail" => (actor.email if actor.email.present? && actor.email_verified_at.present?),
              "memberOf" => group_keys.sort.map { |key| groups_dn.child(:cn, key).to_s },
              "entryUUID" => actor.uuid
            )
          end

          def groups
            held = Group.order(:key).to_a
            members = GroupMember.where(group_id: held.map(&:id), actor_id: listed.select(:id))
                                 .joins(:actor).pluck(:group_id, "actors.nickname", "actors.email")
                                 .group_by(&:first)

            held.map do |group|
              dns = members.fetch(group.id, []).map { |_group, nickname, email| people_dn.child(:uid, nickname.presence || email).to_s }

              Entry.new(
                group_dn(group),
                "objectClass" => %w[top groupOfNames],
                "cn" => group.key,
                "description" => group.name,
                "member" => dns.sort
              )
            end
          end

          def reaches?(container, from, scope)
            case scope
            when BASE then from.parent == container
            when ONE then from == container
            else container.under?(from) || from.under?(container)
            end
          end

          def within?(dn, from, scope)
            case scope
            when BASE then dn == from
            when ONE then dn.parent == from
            else dn.under?(from)
            end
          end

          def matched(from, entries)
            known = entries.map(&:dn)
            ancestor = from.parent

            ancestor = ancestor.parent until ancestor.root? || known.include?(ancestor)
            ancestor.root? ? nil : ancestor
          end
      end
    end
  end
end
