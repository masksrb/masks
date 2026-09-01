class LoginState
  class PromptRequired < StandardError
    attr_reader :prompt

    def initialize(prompt)
      super(prompt.to_s)

      @prompt = prompt.to_s
    end
  end

  class Refused < StandardError
    attr_reader :error, :description

    def initialize(error, description)
      super("#{error}: #{description}")

      @error = error.to_s
      @description = description.to_s
    end
  end

  class << self
    def key
      name.demodulize.underscore.dasherize
    end

    def prompts(name, &condition)
      declared_prompts << [ name.to_s, condition ]
      self
    end

    def handles(*names, &handler)
      names.each { |name| declared_events << [ name.to_s, handler ] }
      self
    end

    def accepts(*names)
      declared_updates.concat(names.map(&:to_sym))
      self
    end

    def declared_prompts
      @declared_prompts ||= inherited_from(:declared_prompts)
    end

    def declared_events
      @declared_events ||= inherited_from(:declared_events)
    end

    def declared_updates
      @declared_updates ||= inherited_from(:declared_updates)
    end

    private

      def inherited_from(name)
        superclass.respond_to?(name) ? superclass.public_send(name).dup : []
      end
  end

  attr_reader :login

  delegate :actor, :client, :identifier, :warn!, :touched?, :factored!, :expire!,
           :updates, :tenant, :request, :session, to: :login

  def initialize(login)
    @login = login
  end

  def key
    self.class.key
  end

  def enabled?
    true
  end

  def as_json
    {}
  end

  def reload!
  end

  def cleanup!
  end

  def start_over!
  end

  def event!(name)
    return unless enabled?

    self.class.declared_events.each do |event, handler|
      instance_exec(&handler) if event == name
    end
  end

  def factor!
    return unless enabled?

    self.class.declared_prompts.each do |prompt, condition|
      prompt!(prompt) if instance_exec(&condition)
    end
  end

  def update(name)
    updates[name.to_s] if self.class.declared_updates.include?(name.to_sym)
  end

  def prompt!(name)
    raise PromptRequired, name
  end

  def refuse!(error, description)
    raise Refused.new(error, description)
  end
end
