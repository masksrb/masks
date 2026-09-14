module Manage
  module Mutations
    class ReadSamlApplicationMetadata < BaseMutation
      NAMES = { "md" => SamlIdentity::METADATA_NS, "ds" => SamlIdentity::DSIG_NS }.freeze

      argument :xml, String

      field :entity_id, String
      field :acs_urls, [ String ], null: false
      field :certificate, String
      field :name_id_format, String
      field :requests_signed, Boolean, null: false

      def resolve(xml:)
        refuse!("that metadata is too large") if xml.bytesize > SamlIdentity::LIMIT
        refuse!("metadata may not declare a document type") if xml.match?(/<!DOCTYPE/i)

        document = Nokogiri::XML(xml) { |config| config.strict.nonet }
        descriptor = document.at_xpath("//md:SPSSODescriptor", NAMES) || refuse!("that is not a service provider's metadata")

        {
          entity_id: descriptor.parent["entityID"],
          acs_urls: descriptor.xpath("md:AssertionConsumerService[@Binding='#{SamlIdentity::POST_BINDING}']", NAMES)
                              .sort_by { |service| service["isDefault"] == "true" ? 0 : 1 }.filter_map { |service| service["Location"] },
          certificate: descriptor.at_xpath("md:KeyDescriptor[not(@use) or @use='signing']//ds:X509Certificate", NAMES)&.text&.gsub(/\s+/, ""),
          name_id_format: descriptor.xpath("md:NameIDFormat", NAMES).map(&:text).map(&:strip).find { |one| SamlIdentity::NAME_ID_FORMATS.include?(one) },
          requests_signed: descriptor["AuthnRequestsSigned"] == "true"
        }
      rescue Nokogiri::XML::SyntaxError
        refuse!("that metadata is not well-formed XML")
      end
    end
  end
end
