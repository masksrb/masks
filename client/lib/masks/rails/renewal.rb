module Masks
  module Rails
    class Renewal
      OUTCOMES = %i[renewed refused unregistered unreachable].freeze

      attr_reader :outcome, :tokens, :identity

      class << self
        def renewed(tokens, identity)
          new(:renewed, tokens: tokens, identity: identity)
        end

        def refused
          new(:refused)
        end

        def unregistered
          new(:unregistered)
        end

        def unreachable
          new(:unreachable)
        end
      end

      def initialize(outcome, tokens: nil, identity: nil)
        raise ArgumentError, "#{outcome.inspect} is not one of #{OUTCOMES.join(', ')}" unless OUTCOMES.include?(outcome)

        @outcome = outcome
        @tokens = tokens
        @identity = identity
      end

      def to_h
        { "outcome" => outcome.to_s, "tokens" => tokens&.to_h&.except("id_token"), "identity" => identity }
      end

      def self.from_h(body)
        return unreachable unless body.is_a?(Hash)

        outcome = OUTCOMES.find { |known| known.to_s == body["outcome"] }

        return unreachable if outcome.nil? || outcome == :unreachable
        return new(outcome) unless outcome == :renewed

        tokens = Masks::Client::Tokens.from_h(body["tokens"])

        return unreachable if tokens.nil? || tokens.access_token.to_s.empty?

        renewed(tokens, body["identity"].is_a?(Hash) ? body["identity"] : nil)
      end
    end
  end
end
