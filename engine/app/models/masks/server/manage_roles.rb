module Masks
  module Server
    module ManageRoles
      OWNER = Scopes::MANAGE
      SECURITY = Scopes::MANAGE_SECURITY
      SUPPORT = Scopes::MANAGE_SUPPORT
      READ = Scopes::MANAGE_READ

      SCOPES = [ OWNER, SECURITY, SUPPORT, READ ].freeze

      LEVELS = {
        read: SCOPES,
        support: [ OWNER, SUPPORT ],
        security: [ OWNER, SECURITY ],
        owner: [ OWNER ]
      }.freeze

      class << self
        def held(scopes)
          Scopes.list(scopes) & SCOPES
        end

        def any?(scopes)
          held(scopes).any?
        end

        def permits?(scopes, level)
          LEVELS.fetch(level).intersect?(held(scopes))
        end

        def owner?(scopes)
          permits?(scopes, :owner)
        end

        def levels(scopes)
          LEVELS.keys.select { |level| permits?(scopes, level) }
        end
      end
    end
  end
end
