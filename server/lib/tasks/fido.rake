namespace :masks do
  namespace :fido do
    desc "Refresh authenticator metadata from the FIDO Metadata Service"
    task refresh: :environment do
      Authenticators.refresh!(out: $stdout)
    rescue Authenticators::Unreachable => e
      abort "masks:fido:refresh — #{e.message}"
    end

    desc "Report what is known about enrolled authenticators"
    task report: :environment do
      known = Authenticator.count

      if known.zero?
        puts "No authenticator metadata. Run masks:fido:refresh."
        next
      end

      puts "#{known} authenticators known, #{Authenticator.compromised.count} with a reported compromise."

      Authenticator.compromised.find_each do |held|
        puts "  #{held.aaguid}  #{held.name}  #{held.compromise}"
      end
    end
  end
end
