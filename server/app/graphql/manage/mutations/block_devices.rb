module Manage
  module Mutations
    class BlockDevices < BaseMutation
      MOST = 500

      argument :ids, [ ID ], required: false
      argument :agent, String, required: false
      argument :refuse, Boolean, required: false

      field :count, Integer, null: false
      field :spared, Boolean, null: false

      def resolve(ids: nil, agent: nil, refuse: false)
        agent = agent&.strip.presence

        refuse!("name devices by ids or by agent, not both") if ids && agent
        refuse!("name devices by ids or by agent") if ids.nil? && agent.nil?
        refuse!("at most #{MOST} devices at once") if ids && ids.size > MOST
        refuse!("refusing an agent needs the agent") if refuse && agent.nil?
        refuse!("MASKS_BLOCKED_AGENTS pins the agents refused here") if refuse && Current.tenant.agents_pinned?

        chosen = ::Device.allowed
        chosen = ids ? chosen.where(id: ids) : chosen.agent_like(agent)

        own = context[:token]&.device_id
        spared = own.present? && chosen.exists?(id: own)
        chosen = chosen.where.not(id: own) if own

        count = 0

        ActiveRecord::Base.transaction do
          chosen.find_each do |device|
            device.block!
            audit!(::Event::DEVICE_BLOCKED, device: device, **(agent ? { agent: agent } : {}))
            count += 1
          end

          remember!(agent) if refuse
        end

        { count: count, spared: spared }
      end

      private

        def remember!(agent)
          tenant = Current.tenant

          return if tenant.agent_list.include?(agent.downcase)

          tenant.blocked_agents = [ tenant.blocked_agents.presence, agent ].compact.join("\n")
          save!(tenant)
        end
    end
  end
end
