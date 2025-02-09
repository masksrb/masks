module Masks
  module Prompts
    class Profile
      include Masks::Prompt

      VISIT = :visit_profile
      VERIFIED = :verify_profile

      match { client.allow_profiles? }

      setup do
        session.structure do
          key VISIT, parent: :entry, expiry: Masks::NEVER_EXPIRE
          key VERIFIED, parent: :entry, expiry: Masks::NEVER_EXPIRE
        end
      end

      event "profile:verify" do
        actor.onboarded!

        session[VISIT] = false
        session[VERIFIED] = true
      end

      event "avatar:upload" do
        next unless auth.upload

        actor.avatar.attach(
          io: auth.upload,
          filename: auth.upload.original_filename,
        )
      end

      event "profile:update" do
        actor.name = updates["name"] if updates["name"]

        warn! "invalid-actor" unless actor.save
      end

      prompt "profile" do
        next if session[VERIFIED]

        if onboarding_required?
          extras(onboarding_required: true)
        elsif session[VISIT] || session.entry["params"]["prompt"]&.presence
          extras(prompted: true)
        end
      end

      def requested!
        session[VISIT] = true
      end

      def visit?
        session[VISIT] || onboarding_required?
      end

      private

      def onboarding_required?
        return true unless actor.onboarded?
        return false unless client.onboarding_expires_in

        onboard_at =
          actor.onboarded_at + Masks.time.duration(client.onboarding_expires_in)

        Time.current > onboard_at
      end
    end
  end
end
