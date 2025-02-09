class ActiveStorage::Service::MasksService < ActiveStorage::Service
  %i[
    upload
    download
    download_chunk
    compose
    delete
    delete_prefixed
    exist?
    private_url
    public_url
    url_for_direct_upload
    custom_metadata_headers
  ].each do |method|
    define_method method do |*args, **options, &block|
      delegate_service.send(method, *args, **options, &block)
    end
  end

  private

  def delegate_service
    adapter = Masks.conf.adapters[Masks.conf.storage_adapter]
    service = adapter.storage_service

    ActiveStorage::Service.configure(
      service,
      { service => { service:, **adapter.config } },
    )
  end
end
