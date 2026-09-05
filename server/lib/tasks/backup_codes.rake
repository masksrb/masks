namespace :masks do
  desc "Generate backup codes for an actor: TENANT=demo ACTOR=owner"
  task backup_codes: :environment do
    tenant = Tenant.active.find_by!(subdomain: ENV.fetch("TENANT"))

    Tenant.switch(tenant) do
      actor = Actor.find_by!(nickname: ENV.fetch("ACTOR"))

      unless actor.otp?
        abort "#{actor.nickname} has no second factor, and a backup code is a way " \
              "past one. Enable an authenticator first."
      end

      puts "Replacing #{actor.backup_codes_remaining} unused codes." if actor.backup_codes?
      puts

      actor.generate_backup_codes!.each { |code| puts "  #{code}" }

      puts
      puts "Shown once. Each works once, in place of the authenticator."
    end
  end
end
