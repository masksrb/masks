class RequestMetrics
  BUCKETS = [ 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10 ].freeze
  ROUTES = %w[authorize token userinfo login manage discovery other].freeze
  EVENT = "process_action.action_controller".freeze

  CONTROLLERS = {
    "Masks::Server::AuthorizeController" => "authorize",
    "Masks::Server::PushedAuthorizationsController" => "authorize",
    "Masks::Server::DeviceAuthorizationsController" => "authorize",
    "Masks::Server::TokensController" => "token",
    "Masks::Server::UserinfoController" => "userinfo",
    "Masks::Server::LoginsController" => "login",
    "Masks::Server::SessionsController" => "login",
    "Masks::Server::DiscoveryController" => "discovery",
    "Masks::Server::ManageController" => "manage"
  }.freeze

  UNCOUNTED = %w[MetricsController HealthController].freeze

  class << self
    def collector
      @collector ||= new
    end

    def subscribe
      ActiveSupport::Notifications.subscribe(EVENT) { |event| collector.record(event) }
    end

    delegate :record, :to_s, to: :collector
  end

  def initialize
    @lock = Mutex.new
    @buckets = ROUTES.to_h { |route| [ route, Array.new(BUCKETS.size + 1, 0) ] }
    @sums = ROUTES.to_h { |route| [ route, 0.0 ] }
    @totals = Hash.new(0)
  end

  def record(event)
    controller = event.payload[:controller].to_s

    return if UNCOUNTED.include?(controller)

    route = route_for(controller)
    seconds = event.duration / 1000.0
    status = status_class(event.payload)

    @lock.synchronize do
      BUCKETS.each_with_index { |bound, index| @buckets[route][index] += 1 if seconds <= bound }
      @buckets[route][BUCKETS.size] += 1
      @sums[route] += seconds
      @totals[[ route, status ]] += 1
    end
  end

  def to_s
    buckets, sums, totals = @lock.synchronize { [ @buckets.transform_values(&:dup), @sums.dup, @totals.dup ] }

    [ histogram(buckets, sums), counter(totals) ].join("\n")
  end

  private

    def route_for(controller)
      return "manage" if controller.start_with?("Masks::Server::Manage::")

      CONTROLLERS.fetch(controller, "other")
    end

    def status_class(payload)
      status = payload[:status] || (payload[:exception] ? 500 : 200)

      "#{status.to_i / 100}xx"
    end

    def histogram(buckets, sums)
      rows = ROUTES.flat_map do |route|
        counts = buckets[route]
        lines = BUCKETS.each_with_index.map do |bound, index|
          %(masks_request_seconds_bucket{route="#{route}",le="#{bound}"} #{counts[index]})
        end
        lines << %(masks_request_seconds_bucket{route="#{route}",le="+Inf"} #{counts.last})
        lines << %(masks_request_seconds_sum{route="#{route}"} #{sums[route].round(6)})
        lines << %(masks_request_seconds_count{route="#{route}"} #{counts.last})
      end

      [ "# HELP masks_request_seconds How long this process took to answer each request, by route.",
        "# TYPE masks_request_seconds histogram", *rows ].join("\n")
    end

    def counter(totals)
      rows = totals.sort.map do |(route, status), count|
        %(masks_requests_total{route="#{route}",status="#{status}"} #{count})
      end

      [ "# HELP masks_requests_total Requests this process answered, by route and status class.",
        "# TYPE masks_requests_total counter", *rows ].join("\n")
    end
end
