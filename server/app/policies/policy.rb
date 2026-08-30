class Policy
  class Denied < StandardError
    attr_reader :error, :description, :status, :redirectable

    def initialize(error, description, status: :bad_request, redirectable: false)
      super("#{error}: #{description}")

      @error = error.to_s
      @description = description.to_s
      @status = status
      @redirectable = redirectable
    end

    def to_h
      { "error" => error, "error_description" => description }
    end
  end

  class << self
    def checks(*names)
      declared.concat(names.map(&:to_sym))
      self
    end

    def uses(*policies)
      used.concat(policies)
      self
    end

    def declared
      @declared ||= inherited_from(:declared)
    end

    def used
      @used ||= inherited_from(:used)
    end

    private

      def inherited_from(name)
        superclass.respond_to?(name) ? superclass.public_send(name).dup : []
      end
  end

  attr_reader :subject

  def initialize(subject)
    @subject = subject
  end

  def call
    self.class.used.uniq.each { |policy| policy.new(subject).call }
    self.class.declared.uniq.each { |name| send(name) }
    self
  end

  def deny!(error, description, status: :bad_request, redirectable: false)
    raise Denied.new(error, description, status: status, redirectable: redirectable)
  end
end
