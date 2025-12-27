module Masks
  class Seeder
    def actor(key, **opts)
      seed!(Masks.actors, key, **opts)
    end

    def client(key, **opts)
      seed!(Masks.clients, key, **opts)
    end

    def provider(key, **opts)
      seed!(Masks.providers, key, **opts)
    end

    private

    def seed!(cls, key, **opts)
      records = (key.respond_to?(:each) ? key : [{ key:, **opts }])
      records.each do |attrs|
        record = cls.seed(**attrs)

        return unless record

        record.seed

        type_name = record.class.name.split("::").last.humanize

        if record.valid?
          Masks.logger.info("#{type_name} '#{record.key}' seeded")
        else
          puts record.errors.full_messages
        end

        record
      end
    end
  end
end
