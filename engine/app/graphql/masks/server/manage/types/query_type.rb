module Masks
  module Server
    module Manage
      module Types
        class QueryType < BaseObject
          field :viewer, ActorType, null: false
          field :manage_levels, [ String ], null: false,
                                            description: "What the viewer's token may do here: read, support, security, and owner."
          field :tenant, TenantType, null: false

          field :actors, [ ActorType ], null: false do
            argument :search, String, required: false
            argument :activated, Boolean, required: false
            argument :holds, String, required: false
            argument :pending_approval, Boolean, required: false
            argument :recovery_requested, Boolean, required: false
            argument :suspended, Boolean, required: false
            argument :after_id, ID, required: false
            argument :limit, Integer, required: false
          end

          field :actor_count, Integer, null: false do
            argument :search, String, required: false
            argument :activated, Boolean, required: false
            argument :holds, String, required: false
            argument :pending_approval, Boolean, required: false
            argument :recovery_requested, Boolean, required: false
            argument :suspended, Boolean, required: false
          end

          field :actor, ActorType do
            argument :uuid, ID
          end

          field :clients, [ ClientType ], null: false do
            argument :search, String, required: false
            argument :archived, Boolean, required: false
            argument :after_id, ID, required: false
            argument :limit, Integer, required: false
          end

          field :client_count, Integer, null: false do
            argument :search, String, required: false
            argument :archived, Boolean, required: false
          end

          field :client, ClientType do
            argument :client_id, ID
          end

          field :sessions, [ SessionType ], null: false do
            argument :actor, ID, required: false
            argument :limit, Integer, required: false
          end

          field :devices, [ DeviceType ], null: false do
            argument :actor, ID, required: false
            argument :blocked, Boolean, required: false
            argument :unattached, Boolean, required: false
            argument :agent, String, required: false
            argument :limit, Integer, required: false
          end

          field :device, DeviceType do
            argument :id, ID
          end

          field :tokens, [ TokenType ], null: false do
            argument :actor, ID, required: false
            argument :client, ID, required: false
            argument :kind, String, required: false
            argument :live, Boolean, required: false
            argument :limit, Integer, required: false
          end

          field :connections, [ ConnectionType ], null: false do
            argument :actor, ID, required: false
            argument :provider, ID, required: false
            argument :revoked, Boolean, required: false
            argument :limit, Integer, required: false
          end

          field :consents, [ ConsentType ], null: false do
            argument :actor, ID, required: false
            argument :client, ID, required: false
            argument :revoked, Boolean, required: false
            argument :limit, Integer, required: false
          end

          field :namespaces, [ NamespaceType ], null: false

          field :providers, [ ProviderType ], null: false do
            argument :archived, Boolean, required: false
          end

          field :provider, ProviderType do
            argument :key, ID
          end

          field :provider_presets, [ ProviderPresetType ], null: false

          field :adapters, [ AdapterType ], null: false do
            argument :kind, String, required: false
            argument :archived, Boolean, required: false
          end

          field :adapter_services, [ AdapterServiceType ], null: false

          field :domain_claims, [ DomainClaimType ], null: false

          field :organizations, [ OrganizationType ], null: false do
            argument :archived, Boolean, required: false
            argument :limit, Integer, required: false, description: "At most this many, by name."
          end

          field :organization, OrganizationType do
            argument :key, ID
          end

          field :event_streams, [ EventStreamType ], null: false do
            argument :archived, Boolean, required: false
          end

          field :sign_in_policies, [ SignInPolicyType ], null: false do
            argument :archived, Boolean, required: false
          end

          field :sign_in_policy, SignInPolicyType do
            argument :key, ID
          end

          field :default_sign_in_policy, SignInPolicyType, null: false

          field :scopes_supported, [ String ], null: false

          field :provisioning_tokens, [ ProvisioningTokenType ], null: false
          field :scim_base_url, String, null: false
          field :saml_metadata_url, String, null: false

          field :minimum_password, Integer, null: false

          field :mail_previews, [ MailPreviewType ], null: false do
            argument :client, ID, required: false
          end

          field :mail_templates, [ MailTemplateType ], null: false,
                description: "One entry for each email the tenant can reword, and the signature."

          field :tally, TallyType, null: false

          field :activity, [ ActivityDayType ], null: false do
            argument :days, Integer, required: false
          end

          field :events, [ EventType ], null: false do
            argument :actor, ID, required: false
            argument :client, ID, required: false
            argument :device, ID, required: false
            argument :action, String, required: false
            argument :grave, Boolean, required: false
            argument :organization, ID, required: false
            argument :after_id, ID, required: false
            argument :limit, Integer, required: false
          end

          field :event_count, Integer, null: false do
            argument :actor, ID, required: false
            argument :client, ID, required: false
            argument :device, ID, required: false
            argument :action, String, required: false
            argument :grave, Boolean, required: false
            argument :organization, ID, required: false
          end

          field :event_actions, [ EventActionType ], null: false

          LIMIT = 50
          CEILING = 200
          SPAN = 30
          LONGEST = 90

          def viewer
            context[:actor]
          end

          def manage_levels
            ManageRoles.levels(context[:roles]).map(&:to_s)
          end

          def tenant
            Current.tenant
          end

          def actors(after_id: nil, limit: nil, **filters)
            scope = actor_scope(**filters).newest_first
            scope = scope.after(Actor.find_by(uuid: after_id)&.id) if after_id.present?

            scope.limit(bounded(limit))
          end

          def actor_count(**filters)
            actor_scope(**filters).count
          end

          def actor(uuid:)
            Actor.find_by(uuid: uuid)
          end

          def provisioning_tokens
            ProvisioningToken.live.order(created_at: :desc)
          end

          def saml_metadata_url
            SamlIdentity.metadata_url(Issuer.new(Current.tenant, Current.origin))
          end

          def mail_previews(client: nil)
            MailPreviews.all(client: client && Client.find_by(client_id: client))
          end

          def mail_templates
            MailTemplate.each_kind
          end

          def scim_base_url
            Scim.base(Issuer.new(Current.tenant, Current.origin))
          end

          def clients(after_id: nil, limit: nil, **filters)
            scope = client_scope(**filters).includes(:approved_by, :namespaces, :sign_in_policy).newest_first
            scope = scope.after(Client.find_by(client_id: after_id)&.id) if after_id.present?

            scope.limit(bounded(limit))
          end

          def client_count(**filters)
            client_scope(**filters).count
          end

          def client(client_id:)
            Client.find_by(client_id: client_id)
          end

          def sessions(actor: nil, limit: nil)
            scope = Session.live.includes(:actor).order(created_at: :desc)
            scope = scope.where(actor: Actor.find_by(uuid: actor)) if actor.present?

            scope.limit(bounded(limit))
          end

          def devices(actor: nil, blocked: nil, unattached: nil, agent: nil, limit: nil)
            scope = Masks::Server::Device.newest_first
            scope = scope.for_actor(Masks::Server::Actor.find_by(uuid: actor)) if actor.present?
            scope = blocked ? scope.blocked : scope.allowed unless blocked.nil?
            scope = scope.where.not(id: signed_in_on) if unattached
            scope = scope.agent_like(agent) if agent.present?

            scope.limit(bounded(limit))
          end

          def device(id:)
            Masks::Server::Device.find_by(id: id)
          end

          def tokens(actor: nil, client: nil, kind: nil, live: true, limit: nil)
            subject = actor.present? ? Actor.find_by(uuid: actor) : nil
            held = client.present? ? Client.find_by(client_id: client) : nil

            return Masks::Server::Token.none if actor.present? && subject.nil?
            return Masks::Server::Token.none if client.present? && held.nil?

            scope = granted.includes(:actor, :client, :device).order(created_at: :desc)
            scope = scope.live if live
            scope = scope.where(actor: subject) if subject
            scope = scope.where(client: held) if held
            scope = scope.where(kind: typed(kind)) if kind.present?

            scope.limit(bounded(limit))
          end

          def connections(actor: nil, provider: nil, revoked: false, limit: nil)
            subject = actor.present? ? Actor.find_by(uuid: actor) : nil
            held = provider.present? ? Masks::Server::Provider.find_by(key: provider) : nil

            return Masks::Server::Connection.none if actor.present? && subject.nil?
            return Masks::Server::Connection.none if provider.present? && held.nil?

            scope = Masks::Server::Connection.includes(:provider, :actor).order(created_at: :desc)
            scope = revoked ? scope.where.not(revoked_at: nil) : scope.live unless revoked.nil?
            scope = scope.where(actor: subject) if subject
            scope = scope.where(provider: held) if held

            scope.limit(bounded(limit))
          end

          def consents(actor: nil, client: nil, revoked: false, limit: nil)
            subject = actor.present? ? Actor.find_by(uuid: actor) : nil
            held = client.present? ? Client.find_by(client_id: client) : nil

            return Masks::Server::Consent.none if actor.present? && subject.nil?
            return Masks::Server::Consent.none if client.present? && held.nil?

            scope = Masks::Server::Consent.includes(:client, :actor).order(updated_at: :desc)
            scope = revoked ? scope.where.not(revoked_at: nil) : scope.live unless revoked.nil?
            scope = scope.where(actor: subject) if subject
            scope = scope.where(client: held) if held

            scope.limit(bounded(limit))
          end

          def namespaces
            Namespace.includes(:client).order(:name)
          end

          def providers(archived: false)
            scope = Masks::Server::Provider.listed(archived)

            scope.order(:name)
          end

          def provider(key:)
            Masks::Server::Provider.find_by(key: key)
          end

          def provider_presets
            Masks::Server::ProviderPreset.all
          end

          def adapters(kind: nil, archived: false)
            scope = Masks::Server::Adapter.listed(archived)
            scope = scope.where(kind: kind) if kind

            scope.order(:kind, primary: :desc, name: :asc)
          end

          def domain_claims
            Masks::Server::DomainClaim.includes(:provider).order(:domain)
          end

          def organizations(archived: false, limit: nil)
            Masks::Server::Organization.listed(archived).order(:name).limit(limit&.clamp(1, 100))
          end

          def organization(key:)
            Masks::Server::Organization.find_by(key: key)
          end

          def event_streams(archived: false)
            Masks::Server::EventStream.listed(archived).order(:name)
          end

          def sign_in_policies(archived: false)
            scope = Masks::Server::SignInPolicy.listed(archived).includes(:clients)

            scope.order(:name)
          end

          def sign_in_policy(key:)
            Masks::Server::SignInPolicy.find_by(key: key)
          end

          def default_sign_in_policy
            Masks::Server::SignInPolicy.for(tenant: Current.tenant)
          end

          def adapter_services
            Masks::Server::Adapter.services.map do |klass|
              { service: klass.service, kind: klass.kind, label: klass.label, fields: klass.fields.map(&:to_h) }
            end
          end

          def scopes_supported
            Scopes::DESCRIBED.keys + Namespace.order(:name).pluck(:name)
          end

          def minimum_password
            Actor::MINIMUM_PASSWORD
          end

          def tally
            {
              actors: Actor.count,
              clients: Client.active.count,
              devices: Masks::Server::Device.allowed.count,
              organizations: Masks::Server::Organization.active.count
            }
          end

          def activity(days: nil)
            span = [ days&.clamp(1, LONGEST) || SPAN, LONGEST ].min
            from = Date.current - (span - 1)

            counted = Session
              .where(authenticated_at: from.beginning_of_day..)
              .group(Arel.sql("DATE(authenticated_at)"))
              .count

            (from..Date.current).map do |on|
              { date: on, sign_ins: counted[on] || 0 }
            end
          end

          def events(after_id: nil, limit: nil, **filters)
            scope = event_scope(**filters).newest_first.includes(:actor, :by, :client, :device, :organization)
            scope = scope.after(after_id) if after_id.present?

            scope.limit(Masks::Server::Event.bounded(limit))
          end

          def event_count(**filters)
            event_scope(**filters).count
          end

          def event_actions
            Masks::Server::Event::ACTIONS.sort
          end

          private

            def actor_scope(search: nil, activated: nil, holds: nil, pending_approval: nil, recovery_requested: nil,
                            suspended: nil)
              scope = Actor.all

              if search.present?
                term = "%#{Actor.sanitize_sql_like(search.strip)}%"
                scope = scope.where("nickname ILIKE :term OR email ILIKE :term OR name ILIKE :term", term: term)
              end

              scope = activated ? scope.where.not(activated_at: nil) : scope.where(activated_at: nil) unless activated.nil?
              scope = holding(scope, holds) if holds.present?
              scope = pending_approval ? scope.where.not(pending_approval_at: nil) : scope.where(pending_approval_at: nil) unless pending_approval.nil?
              scope = suspended ? scope.where.not(suspended_at: nil) : scope.where(suspended_at: nil) unless suspended.nil?
              unless recovery_requested.nil?
                scope = recovery_requested ? scope.where.not(recovery_requested_at: nil) : scope.where(recovery_requested_at: nil)
              end

              scope
            end

            def client_scope(search: nil, archived: false)
              scope = Client.listed(archived)

              return scope if search.blank?

              term = "%#{Client.sanitize_sql_like(search.strip)}%"
              scope.where("name ILIKE :term OR client_id = :exact", term: term, exact: search.strip)
            end

            def event_scope(actor: nil, client: nil, device: nil, action: nil, grave: false, organization: nil)
              subject = actor.present? ? Actor.find_by(uuid: actor) : nil
              group = organization.present? ? Masks::Server::Organization.find_by(key: organization) : nil

              return Masks::Server::Event.none if organization.present? && group.nil?

              held = client.present? ? Client.find_by(client_id: client) : nil
              seen = device.present? ? Masks::Server::Device.find_by(id: device) : nil

              return Masks::Server::Event.none if actor.present? && subject.nil?
              return Masks::Server::Event.none if client.present? && held.nil?
              return Masks::Server::Event.none if device.present? && seen.nil?

              scope = Masks::Server::Event.all
              scope = scope.where(actor: subject) if subject
              scope = scope.where(client: held) if held
              scope = scope.where(device: seen) if seen
              scope = scope.where(organization: group) if group
              scope = scope.where(action: action) if action.present?
              scope = scope.where(action: Masks::Server::Event::GRAVE) if grave

              scope
            end

            def holding(scope, held)
              scope.holding(held)
            end

            def granted
              Masks::Server::Token.where(kind: Types::TokenType::GRANTS)
            end

            def typed(kind)
              raise GraphQL::ExecutionError, "no token kind called #{kind}" unless Types::TokenType::GRANTS.include?(kind.to_s)

              kind.to_s
            end

            def signed_in_on
              Session.where.not(device_id: nil).select(:device_id)
            end

            def bounded(limit)
              [ limit || LIMIT, CEILING ].min
            end
        end
      end
    end
  end
end
