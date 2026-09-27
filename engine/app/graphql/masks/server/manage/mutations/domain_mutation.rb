module Masks
  module Server
    module Manage
      module Mutations
        class DomainMutation < BaseMutation
          private

            def claim!(domain)
              Masks::Server::DomainClaim.find_by(domain: domain.to_s.strip.downcase) || refuse!("no claim on #{domain}")
            end

            def signing_provider!(key)
              return nil if key.blank?

              provider = provider!(key)
              refuse!("#{provider.name} cannot sign anybody in") unless provider.signs_in?

              provider
            end
        end
      end
    end
  end
end
