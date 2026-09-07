class SchemaReference
  SECTIONS = [
    [ "Queries", :query_root ],
    [ "Mutations", :mutation_root ],
    [ "Objects", :objects ],
    [ "Inputs", :inputs ],
    [ "Enums", :enums ],
    [ "Scalars", :scalars ]
  ].freeze

  def initialize(schema)
    @schema = schema
  end

  def page
    [ frontmatter, *SECTIONS.filter_map { |title, source| section(title, send(source)) } ].join("\n")
  end

  private

    attr_reader :schema

    def frontmatter
      <<~HEAD
        ---
        title: Manage API
        description: The GraphQL schema served at /manage/graphql.
        ---

        Everything the console can ask for and everything it can change. `/manage/graphql` accepts a
        bearer carrying `masks:manage`, issued for this tenant's manage resource and no other.

        Generated from `ManageSchema` by `bin/reference`. CI fails when this page and the
        schema disagree.
      HEAD
    end

    def section(title, types)
      return nil if types.empty?

      [ "## #{title}\n", *types.map { |type| describe(type) } ].join("\n")
    end

    def describe(type)
      body = if type.kind.enum?
        values(type)
      elsif type.kind.scalar?
        "A scalar. Serialized as a string unless a client says otherwise.\n"
      else
        fields(type)
      end

      "### #{type.graphql_name}\n\n#{documentation(type)}#{body}"
    end

    def documentation(type)
      described = type.description.to_s.strip

      described.empty? ? "" : "#{described}\n\n"
    end

    def values(type)
      described = type.values.values.map { |value| value.description.to_s.strip }

      rows = type.values.values.zip(described).map do |value, text|
        cells([ "`#{value.graphql_name}`", text ], described)
      end

      table([ "Value", "Description" ], rows, described)
    end

    def fields(type)
      described = type.fields.values.map { |field| field.description.to_s.strip }

      rows = type.fields.values.zip(described).map do |field, text|
        cells([ signature(field), link(field.type), text ], described)
      end

      table([ "Field", "Type", "Description" ], rows, described)
    end

    # A field and its arguments share one cell, each on its own line, so a
    # mutation taking fourteen of them does not set the width of the table.
    def signature(field)
      named = "`#{field.graphql_name}`"
      return named if field.arguments.empty?

      taken = field.arguments.values.map do |argument|
        "<br />`#{argument.graphql_name}: #{argument.type.to_type_signature}`"
      end

      "#{named}#{taken.join}"
    end

    # Every description in this schema is empty, because the code carries no
    # comments. An empty column on every row is noise, so it only appears when
    # something in that table actually filled it in.
    def cells(values, described)
      kept = described.any?(&:present?) ? values : values[0..-2]

      "| #{kept.join(' | ')} |"
    end

    def link(type)
      named = type.unwrap
      shown = type.to_type_signature

      return "`#{shown}`" if named.introspection? || named.kind.scalar?

      "[`#{shown}`](##{named.graphql_name.downcase})"
    end

    def table(headings, rows, described)
      return "None.\n" if rows.empty?

      kept = described.any?(&:present?) ? headings : headings[0..-2]

      [
        "| #{kept.join(' | ')} |",
        "| #{kept.map { '---' }.join(' | ')} |",
        *rows,
        ""
      ].join("\n")
    end

    def declared
      @declared ||= schema.types.values.reject(&:introspection?).sort_by(&:graphql_name)
    end

    def roots
      [ schema.query, schema.mutation ].compact
    end

    def query_root
      [ schema.query ].compact
    end

    def mutation_root
      [ schema.mutation ].compact
    end

    def objects
      declared.select { |type| type.kind.object? } - roots
    end

    def inputs
      declared.select { |type| type.kind.input_object? }
    end

    def enums
      declared.select { |type| type.kind.enum? }
    end

    def scalars
      declared.select { |type| type.kind.scalar? && !type.default_scalar? }
    end
end
