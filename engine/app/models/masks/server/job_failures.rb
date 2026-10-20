module Masks
  module Server
    module JobFailures
      KEEP = 2.days
      PREFIX = "masks:jobs:failed_tenants:".freeze

      module_function

      def record(job, subdomains)
        ::Rails.cache.write("#{PREFIX}#{job}", subdomains.sort, expires_in: KEEP)
      end

      def last(job)
        ::Rails.cache.read("#{PREFIX}#{job}") || []
      end

      def named(jobs)
        jobs.map do |job|
          tenants = last(job)
          tenants.empty? ? job : "#{job} (#{tenants.join(', ')})"
        end
      end
    end
  end
end
