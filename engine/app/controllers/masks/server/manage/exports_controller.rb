module Masks
  module Server
    module Manage
      class ExportsController < ApplicationController
        def show
          export = EventExport.open(params[:token], tenant: current_tenant)

          return head(:not_found) if export.nil?
          exporter = export.exporter

          return head(:forbidden) unless exporter&.manages? && current_actor&.id == exporter.id

          response.headers["Cache-Control"] = "no-store"
          response.headers["X-Content-Type-Options"] = "nosniff"

          send_data export.lines(current_tenant).join, type: "application/x-ndjson",
                                                       filename: export.filename(current_tenant), disposition: "attachment"
        end
      end
    end
  end
end
