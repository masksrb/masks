class RefreshSamlMetadataJob < ApplicationJob
  queue_as :maintenance
  across_tenants!

  def perform
    Tenant.active.find_each do |tenant|
      Tenant.switch(tenant) { refresh }
    end
  end

  private

    def refresh
      Provider.active.where(protocol: Provider::SAML).where.not(metadata_url: [ nil, "" ]).find_each do |provider|
        provider.refresh_metadata!
      rescue Provider::Untrusted, Provider::Refused, Provider::Unreachable, ActiveRecord::RecordInvalid => e
        Rails.logger.warn("saml metadata for #{provider.key} was not refreshed: #{e.message}")
      end
    end
end
