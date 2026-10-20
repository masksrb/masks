module Masks
  module Server
    class Group < ApplicationRecord
      include TenantScoped

      class Sourced < StandardError; end

      KEY = /\A[a-z0-9][a-z0-9._-]*\z/
      MANUAL = "manual".freeze
      RULE = "rule".freeze
      PROVIDER = "provider".freeze
      NESTED = "group".freeze
      SOURCES = [ MANUAL, RULE, PROVIDER, NESTED ].freeze
      SOURCED = [ RULE, PROVIDER, NESTED ].freeze
      SETTINGS = %w[source rule provider_id upstream_group parent_labels].freeze
      WATCHED = (%w[email email_verified_at] + GroupRule::FIELDS).freeze
      PARENTS = 10
      LONGEST = 200

      belongs_to :provider, optional: true
      has_many :members, class_name: "GroupMember", dependent: :delete_all
      has_many :actors, through: :members

      scope :sourced, -> { where(source: SOURCED) }
      scope :ruled, -> { where(source: RULE) }
      scope :filled_by, ->(provider) { where(source: PROVIDER, provider_id: provider.id) }
      scope :nested_under, ->(label) { where(source: NESTED).where("groups.parent_labels @> ?", [ label ].to_json) }
      scope :nested_under_organization, lambda { |key|
        where(source: NESTED).where(
          "EXISTS (SELECT 1 FROM jsonb_array_elements_text(groups.parent_labels) AS label WHERE label LIKE ?)",
          "#{sanitize_sql_like(key)}:%"
        )
      }

      normalizes :key, with: ->(value) { value.to_s.strip.downcase }
      normalizes :name, with: ->(value) { value.to_s.strip }
      normalizes :source, with: ->(value) { value.to_s.strip.downcase.presence || MANUAL }
      normalizes :rule, with: ->(value) { GroupRule.normalize(value) }
      normalizes :upstream_group, with: ->(value) { value.to_s.strip.presence }
      normalizes :parent_labels, with: ->(value) { Array(value).map { |label| label.to_s.strip.downcase }.compact_blank.uniq.sort }

      validates :key, presence: true, format: { with: KEY }, length: { maximum: 64 },
                      uniqueness: { scope: :tenant_id }
      validates :name, presence: true, length: { maximum: 100 }
      validates :source, inclusion: { in: SOURCES }
      validate :source_is_complete

      after_commit :refresh_after_change, on: %i[create update], if: -> { saved_changes.keys.intersect?(SETTINGS) }
      after_commit :refresh_children, on: :destroy

      def sourced?
        SOURCED.include?(source)
      end

      def children
        Group.nested_under(key)
      end

      def add!(actor, by: nil)
        member = members.find_or_create_by!(actor: actor)

        if member.previously_new_record?
          Event.record!(Event::GROUP_JOINED, actor: actor, by: by, group: key)
          settle_children!(actor, by: by)
        elsif member.sourced?
          member.update!(sourced_by: nil)
          Event.record!(Event::GROUP_JOINED, actor: actor, by: by, group: key, kept: true)
        end

        member
      end

      def remove!(actor, by: nil)
        member = members.find_by(actor: actor)

        return false if member.nil?
        raise Sourced, "#{actor.identifier} is in #{name} from its #{source}, so the #{source} decides" if member.sourced?

        member.delete
        Event.record!(Event::GROUP_LEFT, actor: actor, by: by, group: key)
        settle_children!(actor, by: by)

        true
      end

      def refresh!(by: nil, seen: Set.new)
        return self unless seen.add?(id)

        wanted = sourced? ? wanted_actor_ids : []
        held = members.where(sourced_by: source).pluck(:actor_id)
        pinned = members.manual.pluck(:actor_id)
        joining = wanted - held - pinned
        leaving = (held - wanted) | members.sourced.where.not(sourced_by: source).pluck(:actor_id)

        transaction do
          members.sourced.where(actor_id: leaving).delete_all if leaving.any?
          members.insert_all(joining.map { |actor_id| { actor_id: actor_id, tenant_id: tenant_id, sourced_by: source } }) if joining.any?
          update_column(:refreshed_at, Time.current)
        end

        return self if joining.empty? && leaving.empty?

        Event.record!(Event::GROUP_REFRESHED, by: by, group: key, source: source, added: joining.size, removed: leaving.size)
        children.find_each { |child| child.refresh!(by: by, seen: seen) }

        self
      end

      def settle!(actor, by: nil, seen: Set.new)
        return unless seen.add?(id)

        member = members.find_by(actor: actor)

        return if member && !member.sourced?

        if sourced? && wants?(actor)
          return if member&.sourced_by == source

          member ? member.update!(sourced_by: source) : members.create!(actor: actor, sourced_by: source)
          Event.record!(Event::GROUP_JOINED, actor: actor, by: by, group: key, source: source) if member.nil?
        elsif member
          member.delete
          Event.record!(Event::GROUP_LEFT, actor: actor, by: by, group: key, source: member.sourced_by)
        else
          return
        end

        children.find_each { |child| child.settle!(actor, by: by, seen: seen) }
      end

      def wants?(actor)
        case source
        when RULE then GroupRule.scope(rule).exists?(id: actor.id)
        when PROVIDER then provider_connections.exists?(actor_id: actor.id)
        when NESTED then parent_members.exists?(actor_id: actor.id) || parent_memberships.exists?(actor_id: actor.id)
        else false
        end
      end

      def parent_keys
        parent_labels.grep_v(/:/)
      end

      private

        def wanted_actor_ids
          case source
          when RULE then GroupRule.scope(rule).pluck(:id)
          when PROVIDER then provider_connections.distinct.pluck(:actor_id)
          when NESTED then parent_members.distinct.pluck(:actor_id) | parent_memberships.distinct.pluck(:actor_id)
          else []
          end
        end

        def provider_connections
          return Connection.none if provider_id.nil?

          Connection.live.where(provider_id: provider_id).where("connections.upstream_groups @> ?", [ upstream_group ].to_json)
        end

        def parent_members
          GroupMember.joins(:group).where(groups: { key: parent_keys })
        end

        def parent_memberships
          roles = parent_labels.grep(/:/).map { |label| label.split(":", 2) }

          return Membership.none if roles.empty?

          held = roles.map do |key, role|
            Membership.sanitize_sql_array([ "(organizations.key = ? AND memberships.role = ?)", key, role ])
          end

          Membership.accepted.joins(:organization).merge(Organization.active).where(held.join(" OR "))
        end

        def settle_children!(actor, by:)
          children.find_each { |child| child.settle!(actor, by: by) }
        end

        def refresh_after_change
          refresh!
        end

        def refresh_children
          children.find_each(&:refresh!)
        end

        def source_is_complete
          case source
          when RULE then GroupRule.problems(rule).each { |problem| errors.add(:rule, problem) }
          when PROVIDER then provider_is_complete
          when NESTED then parents_are_complete
          end
        end

        def provider_is_complete
          errors.add(:provider, "is needed to fill a group from one") if provider.nil?
          errors.add(:upstream_group, "names the group at the provider") if upstream_group.blank? || upstream_group.length > LONGEST
        end

        def parents_are_complete
          return errors.add(:parent_labels, "name at least one group or organization role") if parent_labels.empty?
          return errors.add(:parent_labels, "name at most #{PARENTS}") if parent_labels.size > PARENTS

          parent_labels.grep_v(Client::ALLOWED_GROUP).each do |label|
            errors.add(:parent_labels, "has #{label}, which is not a group key or key:role")
          end

          (parent_keys - Group.where(key: parent_keys).pluck(:key)).each do |missing|
            errors.add(:parent_labels, "name #{missing}, which is not a group")
          end

          errors.add(:parent_labels, "would put #{name} inside itself") if cycles?
        end

        def cycles?
          pending = parent_keys.dup
          seen = Set.new

          until pending.empty?
            held = pending.shift

            return true if held == key
            next unless seen.add?(held)

            pending.concat(Array(Group.where(key: held, source: NESTED).pick(:parent_labels)).grep_v(/:/))
          end

          false
        end
    end
  end
end
