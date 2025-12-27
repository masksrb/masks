module Masks
  class RequestPolicy
    include Policy
    include SubPolicies
    include RequestMatchers

    ENV_KEY = "masks.request_policy"
    DEFAULT_EXCLUDES = %w[
      /favicon.ico
      /apple-touch-icon*
      /robots.txt
      /sitemap.xml
      /assets/*
      /public/*
      /.well-known/*
    ].freeze

    checks :request do
      policy = masks_policy

      next if policy.path_matches?(request.path, policy.excluded)

      matches = []

      masks_policy.policies.each do |p|
        matches << p if p.request_matches?(request)
      end

      matches.each do |p|
        p.check(:request, p, context: self)
      end
    end

    def excluded
      @excluded ||= DEFAULT_EXCLUDES.dup
    end
  end
end
