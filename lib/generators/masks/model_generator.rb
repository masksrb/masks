# frozen_string_literal: true
require "rails/generators/active_record"

class Masks::ModelGenerator < Rails::Generators::Base
  def create_model
    return help unless key&.present?

    model = find_model

    keys =
      if updates.keys.any?
        model ||= build_model
        model.assign_attributes(updates)

        created = model.new_record?

        model.save!

        log type_name, "'#{key}' #{created ? "created" : "saved"}..."

        if created
          ["key", *setting_keys].uniq
        else
          changed = attrs.keys.map(&:to_s) & settings.keys

          ["key", *changed].uniq
        end
      elsif model
        log type_name, "'#{key}' found..."

        ["id", "key", *setting_keys].uniq
      else
        self.behavior = :stderr

        log type_name, "not found..."

        return
      end

    table =
      keys.map do |key|
        value = JSON.generate(model.send(key))

        [key, filter_value(key, value)]
      rescue => e
        [key, nil]
      end

    shell.print_table(table, indent:)
  rescue ActiveRecord::RecordInvalid
    self.behavior = :stderr

    model.errors.full_messages.each { |msg| log type_name, msg }
  rescue => e
    self.behavior = :stderr

    log type_name, e.to_s

    puts e.backtrace
  end

  private

  def filter_value(key, value)
    ENV["SHOW_SECRETS"] ? value : Masks.filter_param(key, value)
  end

  def indent
    12 - type_name.length
  end

  def settings_table(settings)
    table = settings.map { |k, v| [k, v.fetch(:desc, nil)] }
    shell.print_table(table, indent:)
  end

  def help
    return if @helped

    @helped = true
    header = <<-HELP
  [key] [...setting=value]

  View, add and edit #{type_name.pluralize}.
  ---
  Prints public settings if none are passed. For example:

  $ masks #{type_name} foo

  Otherwise, creates new records for unknown keys.

  $ masks #{type_name} foobar setting=...

  And similarly edits existing records, if found.

  $ masks #{type_name} foobar setting=abc
  $ masks #{type_name} foobar setting=123

  Available settings:

      HELP

    log type_name, header
    table = setting_keys.map { |s| [s, settings.dig(s, :desc)] }

    shell.print_table(table, indent:)

    notes = help_notes

    if notes
      puts
      log "note", notes
      puts
    end
  end

  def help_notes
    # Nothing by default
  end

  def type_name
    self.class.name.split("::").last.underscore.gsub(/_generator/, "")
  end

  def key
    @key ||= ARGV[0]
  end

  def updates
    @updates ||=
      attrs
        .map do |k, v|
          conf = settings[k.to_s]

          [k, v] if conf && conf[:writable]
        end
        .compact
        .to_h
  end

  def attrs
    @attrs ||=
      (ARGV.slice(1...) || [])
        .map do |attr|
          if attr.include?("=")
            name, value = attr.split("=", 2)

            [name, value]
          end
        end
        .compact
        .to_h
        .symbolize_keys
  end

  def find_model
    raise NotImplementedError
  end

  def build_model
    raise NotImplementedError
  end

  def settings
    {}
  end

  def setting_keys
    [*preferred_keys, *settings.keys.map(&:to_s)].uniq
  end

  def preferred_keys
    []
  end
end
