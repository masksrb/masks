require "rdoc"
require "fileutils"
require "prism"

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

  Entry = Struct.new(:sigil, :name, :params, :comment) do
    def order
      [ sigil == "::" ? 0 : 1, name ]
    end
  end

  # Prism, rather than RDoc, because RDoc stopped reading the bodies of blocks
  # and a Concern's class methods live in one.
  class ClassMethods
    BLOCK = "class_methods".freeze

    def initialize(source)
      @source = source
    end

    def of(full_name)
      found = []
      walk(Prism.parse(@source).value, [], full_name, found)
      found
    end

    private

      def walk(node, path, target, found)
        node.compact_child_nodes.each do |child|
          unless child.is_a?(Prism::ModuleNode) || child.is_a?(Prism::ClassNode)
            walk(child, path, target, found)
            next
          end

          here = path + [ child.constant_path.slice ]

          collect(child, found) if here.join("::") == target
          walk(child.body, here, target, found) if child.body
        end
      end

      def collect(mod, found)
        return unless mod.body

        mod.body.compact_child_nodes.each do |statement|
          next unless opens_class_methods?(statement)

          statement.block.body.compact_child_nodes.each do |inner|
            next unless inner.is_a?(Prism::DefNode) && inner.receiver.nil?

            found << Entry.new("::", inner.name.to_s, "(#{inner.parameters&.slice})", nil)
          end
        end
      end

      def opens_class_methods?(node)
        node.is_a?(Prism::CallNode) &&
          node.name.to_s == BLOCK &&
          node.receiver.nil? &&
          node.block.is_a?(Prism::BlockNode) &&
          !node.block.body.nil?
      end
  end

  def self.setup_options(options)
    options.option_parser&.separator ""
  end

  def initialize(store, options)
    @store = store
    @options = options

    # RDoc chdirs into the output directory before calling generate, so a
    # relative op_dir would nest itself inside the run.
    @out = File.expand_path(options.op_dir)
    @sources = Dir.pwd
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
      parsed = mod.method_list
                  .select { |method| method.visibility == :public }
                  .map { |method| Entry.new(method.singleton ? "::" : "#", method.name, method.params, method.comment) }

      (parsed + concerned(mod)).sort_by(&:order).map { |entry| method_entry(entry) }
    end

    # A method defined in a Concern's class_methods block belongs to whatever
    # includes the module, and RDoc does not descend into the block to find it.
    def concerned(mod)
      mod.in_files.flat_map do |file|
        path = File.expand_path(file.absolute_name, @sources)
        next [] unless File.file?(path)

        ClassMethods.new(File.read(path)).of(mod.full_name)
      end
    end

    # RDoc wraps a long signature across lines; a fenced one line reads better
    # and is what the page held before.
    def method_entry(entry)
      signature = "#{entry.sigil}#{entry.name}#{one_line(entry.params)}"

      [
        "### #{entry.sigil}#{entry.name}\n",
        "```ruby\n#{signature}\n```\n",
        prose(entry.comment)
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
        .gsub(%r{<code>(.+?)</code>}m) { "`#{Regexp.last_match(1).gsub(/\s+/, ' ')}`" }
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
