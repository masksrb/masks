module Masks
  module Server
    module Manage
      module Sources
        class MembershipCounts < GraphQL::Dataloader::Source
          def initialize(kind)
            @kind = kind
          end

          def fetch(ids)
            counted = relation.where(organization_id: ids).group(:organization_id).count

            ids.map { |id| counted.fetch(id, 0) }
          end

          private

            def relation
              case @kind
              when :members then Masks::Server::Membership.accepted
              when :owners then Masks::Server::Membership.accepted.where(role: Masks::Server::Organization::OWNER)
              when :pending then Masks::Server::Membership.outstanding
              end
            end
        end
      end
    end
  end
end
