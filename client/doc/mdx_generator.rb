require "rdoc"
require "fileutils"

# Emits the gem's API as Astro pages, so it reads as part of the docs rather
# than as a second site beside them. Registered with RDoc as `--format mdx`.
#
# One page per top-level namespace: Masks::Client and Masks::Rails. Classes are
# h2 and their methods h3, which is what Starlight builds its table of contents
# from.
class RDoc::Generator::Mdx
  RDoc::RDoc.add_generator self

  PAGES = {
    "Masks::Client" => {
      file: "ruby.mdx",
      title: "Masks::Client",
      description: "The protocol half of the masks gem: discovery, PKCE, exchange, verification."
    },
    "Masks::Rails" => {
      file: "rails.mdx",
      title: "Masks::Rails",
      description: "The Rails engine that mounts the code flow into an application."
    }
  }.freeze

  def self.setup_options(options)
    options.option_parser&.separator ""
  end

  def initialize(store, options)
    @store = store
    @options = options

    # RDoc chdirs into the output directory before calling generate, so a
    # relative op_dir would nest itself inside the run.
    @out = File.expand_path(options.op_dir)
  end

  def generate
    FileUtils.mkdir_p(@out)

    PAGES.each do |root, page|
      held = documented.select { |mod| mod.full_name == root || mod.full_name.start_with?("#{root}::") }
      next if held.empty?

      File.write(File.join(@out, page[:file]), body(root, page, held))
    end
  end

  private

    def documented
      @documented ||= @store.all_classes_and_modules
                            .reject { |mod| mod.full_name.start_with?("RDoc") }
                            .sort_by(&:full_name)
    end

    def body(root, page, held)
      lede = held.find { |mod| mod.full_name == root }

      [
        heading(page),
        prose(lede&.comment),
        "Generated from `client/lib` by `bundle exec rake reference`. Its shape is the code's; the\n" \
        "prose is the RDoc in the source.\n",
        *held.reject { |mod| mod.full_name == root }.map { |mod| describe(mod) }
      ].compact.join("\n")
    end

    # Quoted, because both a namespace and a sentence carry colons and YAML
    # would read them as mappings.
    def heading(page)
      <<~HEAD
        ---
        title: #{page[:title].inspect}
        description: #{page[:description].inspect}
        ---

      HEAD
    end

    def describe(mod)
      [
        "## #{mod.full_name}\n",
        kind(mod),
        prose(mod.comment),
        constants(mod),
        attributes(mod),
        *methods_of(mod)
      ].compact.join("\n")
    end

    # NormalModule answers respond_to?(:superclass) and then raises, so ask
    # what it is rather than what it answers.
    def kind(mod)
      return nil if mod.module?

      parent = mod.superclass
      return nil unless parent

      name = parent.is_a?(String) ? parent : parent.full_name
      return nil if name.nil? || name == "Object"

      "Inherits `#{name}`.\n"
    end

    def constants(mod)
      return nil if mod.constants.empty?

      described = mod.constants.map { |const| inline(const.comment) }
      rows = mod.constants.zip(described).map do |const, text|
        cells([ "`#{const.name}`", "`#{one_line(const.value)}`", text ], described)
      end

      table([ "Constant", "Value", "Description" ], rows, described)
    end

    def attributes(mod)
      return nil if mod.attributes.empty?

      shown = mod.attributes.sort_by(&:name)
      described = shown.map { |attr| inline(attr.comment) }
      rows = shown.zip(described).map do |attr, text|
        cells([ "`#{attr.name}`", attr.rw, text ], described)
      end

      table([ "Attribute", "Access", "Description" ], rows, described)
    end

    def methods_of(mod)
      mod.method_list
         .select { |method| method.visibility == :public }
         .sort_by { |method| [ method.singleton ? 0 : 1, method.name ] }
         .map { |method| method_entry(method) }
    end

    def method_entry(method)
      sigil = method.singleton ? "::" : "#"
      params = method.params.to_s.strip

      [
        "### #{sigil}#{method.name}\n",
        "```ruby\n#{sigil}#{method.name}#{params}\n```\n",
        prose(method.comment)
      ].compact.join("\n")
    end

    # Most of this gem carries no RDoc yet, so a Description column would be
    # empty on every row. It appears when something has filled it in.
    def cells(values, described)
      "| #{(described.any? { |text| !text.empty? } ? values : values[0..-2]).join(' | ')} |"
    end

    def table(headings, rows, described)
      kept = described.any? { |text| !text.empty? } ? headings : headings[0..-2]

      [
        "| #{kept.join(' | ')} |",
        "| #{kept.map { '---' }.join(' | ')} |",
        *rows,
        ""
      ].join("\n")
    end

    # RDoc markup is not Markdown — +code+, <tt>, [term] lists and indented
    # code blocks all have to go through its own formatter first.
    def prose(comment)
      text = raw(comment)
      return nil if text.empty?

      markdown = tidy(RDoc::Comment.new(text).parse.accept(RDoc::Markup::ToMarkdown.new).to_s)
      return nil if markdown.empty?

      "#{safe(markdown)}\n"
    end

    # ToMarkdown emits an h1 for `= Heading`, which duplicates the title the
    # page already has, and Pandoc definition lists, which remark does not
    # parse — both are rewritten into something MDX renders.
    def tidy(markdown)
      markdown
        .sub(/\A\s*#\s+[^\n]*\n+/, "")
        .gsub(/^(\S[^\n]*)\n:   ([^\n]*)$/) { "- **#{Regexp.last_match(1)}** — #{Regexp.last_match(2)}" }
        .strip
    end

    # ClassModule#comment is a String, not a Comment, and it concatenates one
    # blob per file the class is opened in — joined by a --- rule, most of them
    # empty. Keep the ones that said something.
    def raw(comment)
      text =
        case comment
        when nil then ""
        when String then comment
        else comment.respond_to?(:text) ? comment.text.to_s : comment.to_s
        end

      text.split(/^-{3,}$/).map(&:strip).reject(&:empty?).join("\n\n")
    end

    def inline(comment)
      prose(comment).to_s.gsub(/\s+/, " ").strip
    end

    def one_line(value)
      value.to_s.gsub(/\s+/, " ").strip
    end

    # MDX parses JSX, so a bare < or { in prose is a syntax error. Code spans
    # and fences are left alone; everything around them is escaped.
    def safe(text)
      text.split(/(```.*?```|`[^`\n]*`)/m).each_slice(2).flat_map do |plain, code|
        [ plain&.gsub("<", "&lt;")&.gsub("{", "&#123;")&.gsub("}", "&#125;"), code ]
      end.compact.join
    end
end
