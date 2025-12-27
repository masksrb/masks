module Masks
  module SubPolicies
    def policies
      @policies ||= []
    end

    def uses(name)
      policies.push(*Masks.policy(name).policies)
    end

    def add(type, **opts, &block)
      policy = case type
      when Symbol, String
        Masks.cls("#{type}_policy").new(**opts)
      when Hash
        Masks.cls("#{type[:type]}_policy").new(**type.except(:type))
      else
        type.dup if type.class.include?(Policy)
      end

      policy.run(&block) if block && policy.respond_to?(:run)
      policies << policy if policy

      self
    end

    private

    def default_policies
      nil
    end

    def before_init
      run { default_policies }
    end

    def after_copy(copy)
      @policies = copy.policies.dup if copy.respond_to?(:policies)
    end
  end
end
