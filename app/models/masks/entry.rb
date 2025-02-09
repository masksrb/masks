module Masks
  class Entry
    FACTOR1 = :first_factor
    FACTOR2 = :second_factor

    class << self
      def enter(*args, **opts)
        new(*args, **opts).tap { |e| e.enter! }
      end
    end

    attr_reader :session, :raw_params
    attr_writer :prompt
    attr_accessor :event
    attr_accessor :scopes
    attr_accessor :error

    def initialize(session, **params)
      @session = session
      @raw_params = params
    end

    delegate :request_id, to: :session

    def id
      session_key
    end

    def path
      session.rails_request.path
    end

    def params
      raise NotImplementedError
    end

    def client
      raise NotImplementedError
    end

    def conf
      Masks.conf
    end

    def settings
      conf.public_settings
    end

    def actor
      if settled?
        @actor ||= Masks::Actor.find(settlement["actor"]) if settlement["actor"]
      else
        session.current_actor
      end
    end

    attr_accessor :login_link

    def event?(name)
      event && event.to_s == name.to_s
    end

    def updates
      {}
    end

    def trusted?
      @entered && session[FACTOR1] && session[FACTOR2]
    end

    def redirect_uri
      settlement["redirect_uri"] if settled?
    end

    def settled!(prompt: "success", error: nil, redirect_uri: nil)
      if error
        self.prompt = error
      else
        self.prompt = prompt
      end

      if session.structure.bag?(:entry)
        session.entry["settlement"] = {
          "settled" => true,
          "prompt" => self.prompt,
          "redirect_uri" => redirect_uri,
          "actor" => actor&.id,
        }

        error ? dispatch("failed") : dispatch("login")

        session.entry.refresh(request_id)
      end

      @settled = true
    end

    def settlement
      if @entered
        session.entry["settlement"] ||= {}
      else
        {}
      end
    end

    def settled?
      @settled || session.entry&.data&.dig("settlement", "settled")
    end

    def warnings
      @warnings ||= []
    end

    def warn!(*keys, prompt: nil)
      warnings << keys.compact.join(":")
      @warnings.uniq!

      self.prompt = prompt if prompt
    end

    def extras(**additions)
      @extras ||= {}
      @extras.deep_merge!(additions)
      @extras
    end

    def session_key
      raise NotImplementedError
    end

    def session_lifetime
      nil
    end

    def enter!
      return if @entered

      device_class = conf.device_class.constantize

      session.structure do
        device device_class,
               expiry: device_class.cleanup_at || Masks::NEVER_EXPIRE
      end

      return settled!(error: "missing-client") unless client

      @entered = true
      client = self.client

      session.structure do
        current :entry,
                parent: :device,
                expiry: -> { client.expires_at(:login_attempt) }
        current :client, parent: :device, expiry: Masks::NEVER_EXPIRE
        current :actor, parent: :device, expiry: Masks::NEVER_EXPIRE
        current :manager, parent: :device, expiry: Masks::NEVER_EXPIRE
        current :identifier,
                parent: :entry,
                track: true,
                expiry: Masks::NEVER_EXPIRE,
                null: true
      end

      session[:entry] = self
      session[:client] = client

      dispatch(Prompt::SETUP)

      enter

      dispatch(Prompt::CLEANUP)

      session.deep_clean
      session.device.refresh

      self
    end

    def prompt
      error || @prompt || settlement["prompt"]
    end

    def prompts
      @prompts ||=
        Masks.conf.prompts.map { |cls| [cls.to_s, cls.new(self)] }.to_h
    end

    def prompt!
      dispatch(Prompt::PREAUTH)
      dispatch(event:) if event
      dispatch(Prompt::AUTH)
      dispatch(Prompt::POSTAUTH)
    end

    def dispatch(*args, **opts)
      prompts.values.each { |p| p.dispatch(*args, **opts) }
    end

    def to_gql
      # Check out this amazing hack...

      @gql ||=
        begin
          json =
            MasksSchema.execute(
              "
              mutation {
                entry(input: {}) {
                  entry {
                    ...EntryFragment
                  }
                }
              }

              #{MasksSchema.entry_gql}
            ",
              context: {
                entry: self,
                serialize: true,
              },
            ).as_json

          puts json
          data = json.dig("data", "entry")

          raise AuthError unless data

          data
        end
    end

    private

    def enter
      nil
    end
  end
end
