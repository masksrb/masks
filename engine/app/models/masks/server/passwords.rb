module Masks
  module Server
    module Passwords
      COMMON = Set.new(File.foreach(Engine.root.join("config/passwords/common.txt"), chomp: true)).freeze

      class << self
        def common?(password)
          COMMON.include?(password.to_s.downcase)
        end

        def refusal(password, policy)
          return "short-password" if password.to_s.length < policy.password_minimum
          return "common-password" if policy.refuse_common_passwords && common?(password)

          nil
        end
      end
    end
  end
end
