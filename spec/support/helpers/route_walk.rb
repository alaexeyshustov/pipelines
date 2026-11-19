# Flattens every route the app serves, including mounted engines, into
# { verb:, path:, action: } entries with dummy values in dynamic segments.
module RouteWalk
  # Reachable without a login: the health check and the login form itself.
  OPEN_PATHS = [ "/up" ].freeze
  OPEN_ACTIONS = %w[sessions#new sessions#create].freeze
  # ViewComponent's previews and system-test entrypoint are drawn only outside production.
  EXCLUDED_PREFIXES = %w[/rails/view_components /_system_test_entrypoint].freeze
  DUMMY_SEGMENTS = { "status" => "failed", "application_id" => "x" }.freeze

  module_function

  def entries
    @entries ||= Rails.application.routes.routes.flat_map { |route| route.dispatcher? ? [ entry(route, "") ] : mounted_entries(route) }
  end

  # Entries the login must protect.
  def walked
    entries.reject { |entry| open?(entry) || excluded?(entry) || entry[:verb].blank? }
  end

  def open_entries
    entries.select { |entry| open?(entry) }
  end

  # Prefixes of mounted apps the walk cannot enter (not a Rails engine) and that nobody excluded.
  def uncovered_mounts
    mounts.reject { |route| engine_of(route) || EXCLUDED_PREFIXES.any? { |prefix| route.path.spec.to_s.start_with?(prefix) } }
          .map { |route| route.path.spec.to_s }
  end

  def mount_prefixes
    mounts.map { |route| route.path.spec.to_s }
  end

  def mounts
    Rails.application.routes.routes.reject(&:dispatcher?)
  end

  def mounted_entries(route)
    engine = engine_of(route)
    engine ? engine.routes.routes.map { |inner| entry(inner, route.path.spec.to_s) } : []
  end

  def engine_of(route)
    app = route.app.respond_to?(:app) ? route.app.app : route.app
    app if app.is_a?(Class) && app < Rails::Engine
  end

  def entry(route, prefix)
    { verb: route.verb, path: path_for(prefix, route.path.spec.to_s), action: "#{route.defaults[:controller]}##{route.defaults[:action]}" }
  end

  def path_for(prefix, spec)
    path = "#{prefix}#{spec.sub('(.:format)', '')}".gsub(/:(\w+)/) { DUMMY_SEGMENTS.fetch(Regexp.last_match(1), "1") }
    path.length > 1 ? path.chomp("/") : path
  end

  def open?(entry)
    OPEN_PATHS.include?(entry[:path]) || OPEN_ACTIONS.include?(entry[:action])
  end

  def excluded?(entry)
    EXCLUDED_PREFIXES.any? { |prefix| entry[:path].start_with?(prefix) }
  end
end
