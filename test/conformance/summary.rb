#!/usr/bin/env ruby
require "json"

log = ARGV[0] || File.join(__dir__, "results", "run.log")
out = ARGV[1] || File.join(__dir__, "results", "summary.json")
ansi = /\e\[[0-9;]*m/
plans = []

File.foreach(log) do |raw|
  line = raw.gsub(ansi, "")

  if (plan = line[/Results for \[\d+\] (\S+) with configuration/, 1])
    plans << { "plan" => plan, "modules" => Hash.new(0), "conditions" => {} }
  elsif (status = line[/FINISHED - result (\w+)\./, 1]) && plans.last
    plans.last["modules"][status] += 1
  elsif (totals = line.match(/Overall totals: ran (\d+) test modules\. Conditions: (\d+) successes, (\d+) failures, (\d+) warnings/)) && plans.last
    plans.last["conditions"] = {
      "modules" => totals[1].to_i,
      "successes" => totals[2].to_i,
      "failures" => totals[3].to_i,
      "warnings" => totals[4].to_i
    }
  end
end

abort "no plans found in #{log}" if plans.empty?

statuses = %w[PASSED REVIEW WARNING FAILED SKIPPED INTERRUPTED]
rows = plans.map do |plan|
  counts = statuses.map { |status| plan["modules"].fetch(status, 0) }
  conditions = plan["conditions"]
  [ plan["plan"].sub("-certification-test-plan", ""), *counts, conditions["successes"], conditions["failures"], conditions["warnings"] ]
end
totals = rows.transpose.drop(1).map { |column| column.compact.sum }

table = [
  "| Plan | Passed | Review | Warning | Failed | Skipped | Interrupted | Conditions met | Conditions failed | Conditions warned |",
  "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
  *rows.map { |row| "| #{row.join(' | ')} |" },
  "| **All plans** | #{totals.map { |n| "**#{n}**" }.join(' | ')} |"
].join("\n")

File.write(out, JSON.pretty_generate({ "plans" => plans, "totals" => statuses.zip(totals).to_h.merge("conditions_met" => totals[6], "conditions_failed" => totals[7], "conditions_warned" => totals[8]) }))

summary = ENV["GITHUB_STEP_SUMMARY"]
File.open(summary, "a") { |f| f.puts("## OpenID conformance", "", table, "") } if summary
puts table
