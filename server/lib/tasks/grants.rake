namespace :masks do
  desc "Grant MASKS_SERVING_USER the table access it serves with, run as the role that migrates"
  task grants: :environment do
    DatabaseGrants.grant_everywhere!(ENV["MASKS_SERVING_USER"])
  rescue DatabaseGrants::Refused => e
    abort "masks: #{e.message}"
  end
end
