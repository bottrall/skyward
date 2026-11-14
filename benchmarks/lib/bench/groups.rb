# frozen_string_literal: true

# rbs_inline: enabled

# Each group runs in a Ruby of its own, since an app connects to one database,
# and so no group's garbage or JIT warmup lands in another's numbers. A
# scenario's name starts with its group's.
module Bench::Groups
  extend self

  ALL = %w[api orm.sqlite orm.postgresql].freeze #: Array[String]

  # @rbs group: String
  # @rbs return: Array[Bench::Scenario]
  def scenarios(group) = group == 'api' ? Bench::Requests.scenarios : Bench::Queries.scenarios(group)

  # @rbs names: Array[String]
  # @rbs scenario_names: Array[String]
  # @rbs return: Array[String]
  def unmatched(names, scenario_names)
    names.reject { |name| scenario_names.any? { |scenario_name| scenario_name.start_with?(name) } }
  end

  # @rbs names: Array[String]
  # @rbs return: Array[String]
  def selected(names)
    return ALL if names.empty?

    ALL.select { |group| names.any? { |name| group.start_with?(name) || name.start_with?("#{group}.") } }
  end

  # @rbs groups: Array[String]
  # @rbs postgres_url: String?
  # @rbs return: Hash[String, String]
  def skipped(groups, postgres_url)
    return {} unless postgres_url.nil? && groups.include?('orm.postgresql')

    { 'orm.postgresql' => "TEST_POSTGRES_URL isn't set" }
  end

  # @rbs scenarios: Array[Bench::Scenario]
  # @rbs names: Array[String]
  # @rbs return: Array[Bench::Scenario]
  def matching(scenarios, names)
    return scenarios if names.empty?

    scenarios.select { |scenario| names.any? { |name| scenario.name.start_with?(name) } }
  end
end
