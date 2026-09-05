module Authenticators
  class Unreachable < StandardError; end

  BUNDLED = Rails.root.join("db/authenticators.yml")

  def self.refresh!(store: FidoMetadata::Store.new, out: nil)
    counted = { mds: 0, bundled: 0, compromised: 0 }

    each_entry(store) do |entry|
      held = record(entry)
      next if held.nil?

      counted[:mds] += 1
      counted[:compromised] += 1 if held.compromised?
    end

    counted[:bundled] = fill_gaps
    out&.puts(summary(counted))
    counted
  end

  def self.each_entry(store)
    store.table_of_contents.entries.each { |entry| yield entry }
  rescue StandardError => e
    raise Unreachable, "the metadata service could not be read: #{e.class}: #{e.message}"
  end

  def self.record(entry)
    aaguid = entry.aaguid.presence
    return nil if aaguid.nil?

    statuses = Array(entry.status_reports).map { |report| report.status.to_s }.reject(&:blank?)
    statement = entry.metadata_statement

    upsert(
      aaguid: aaguid,
      name: statement&.description.presence || aaguid,
      source: Authenticator::MDS,
      icon: statement&.icon,
      certification: Authenticator.certification_in(statuses),
      statuses: statuses,
      compromised_at: Authenticator.compromise_in(statuses) ? Time.current : nil
    )
  end

  def self.fill_gaps
    return 0 unless BUNDLED.exist?

    known = Authenticator.where(source: Authenticator::MDS).pluck(:aaguid).to_set

    YAML.safe_load_file(BUNDLED).reject { |aaguid, _| known.include?(aaguid) }.count do |aaguid, name|
      upsert(aaguid: aaguid, name: name, source: Authenticator::BUNDLED, statuses: [])
    end
  end

  def self.upsert(aaguid:, name:, source:, statuses:, icon: nil, certification: nil, compromised_at: nil)
    held = Authenticator.find_or_initialize_by(aaguid: aaguid)

    return held if held.persisted? && held.authoritative? && source == Authenticator::BUNDLED

    held.update!(
      name: name, source: source, icon: icon,
      certification: certification, statuses: statuses,
      compromised_at: compromised_at
    )

    held
  end

  def self.summary(counted)
    "#{counted[:mds]} from the metadata service, #{counted[:bundled]} bundled, " \
      "#{counted[:compromised]} with a reported compromise"
  end
end
