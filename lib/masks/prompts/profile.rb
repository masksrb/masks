module Masks
  module Prompts
    class Profile
      include Masks::Prompt

      setting :name, :string
      setting :new_password, :string

      VISIT = :visit_profile
      VERIFIED = :verify_profile

      match { current_client.allow_profiles? }

      setup do
        session.structure do
          key VISIT, parent: :endpoint, expiry: Masks::NEVER_EXPIRE
          key VERIFIED, parent: :endpoint, expiry: Masks::NEVER_EXPIRE
        end
      end

      event "profile:visit" do
        requested!

        self.prompt = "profile"
      end

      event "profile:verify" do
        current_actor.onboarded!

        session[VISIT] = false
        session[VERIFIED] = true
      end

      event "password:change", trusted: true, factors: FIRST_OR_SECOND do
        current_actor.overwrite_password(new_password)

        warn! "invalid-password" unless current_actor.save
      end

      event "avatar:upload" do
        next unless auth.upload

        current_actor.avatar.attach(
          io: auth.upload,
          filename: auth.upload.original_filename,
        )
      end

      event "profile:update" do
        current_actor.name = name if name

        warn! "invalid-actor" unless current_actor.save
      end

      prompt "profile" do
        next if session[VERIFIED]

        if onboarding_required?
          extras(onboarding_required: true)
        elsif session[VISIT] || prompted?
          extras(prompted: true)
        end
      end

      def requested!
        session[VISIT] = true
      end

      def visit?
        session[VISIT] || onboarding_required?
      end

      def prompted?
        login.prompt_hint == "profile"
      end

      private

      def onboarding_required?
        return true unless current_actor.onboarded?
        return false unless current_client.onboarded_profile_duration

        onboard_at =
          current_actor.onboarded_at +
            current_client.duration(:onboarded_profile)

        Time.current > onboard_at
      end
    end
  end
end
