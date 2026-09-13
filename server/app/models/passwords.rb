module Passwords
  LIST = Rails.root.join("config/passwords/common.txt")

  class << self
    def common?(password)
      common.include?(password.to_s.downcase)
    end

    def refusal(password, policy)
      return "short-password" if password.to_s.length < policy.password_minimum
      return "common-password" if policy.refuse_common_passwords && common?(password)

      nil
    end

    private

      def common
        @common ||= Set.new(File.foreach(LIST, chomp: true))
      end
  end
end
