module Masks
  module Shims
    class << self
      def rack_env(method, path, query, session: nil)
        base = {
          "REQUEST_METHOD" => method.to_s.upcase,
          "PATH_INFO" => path,
          "QUERY_STRING" => query.to_query,
          "rack.session" => session,
        }

        base
      end
    end
  end
end
