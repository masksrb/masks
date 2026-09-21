module ServesPictures
  SEALED = "default-src 'none'; sandbox".freeze
  FOREVER = 1.year.to_i
  BRIEFLY = 5.minutes.to_i

  private

    def deliver_picture(stamp, cache_control:, vary: nil)
      response.headers["X-Content-Type-Options"] = "nosniff"
      response.headers["Content-Security-Policy"] = SEALED
      response.headers["Cache-Control"] = cache_control
      response.headers["Vary"] = vary if vary
      response.headers["ETag"] = %("#{stamp}")

      return head :not_modified if request.headers["If-None-Match"].to_s.include?(stamp)

      content_type, bytes = yield

      return head :not_found if bytes.nil?

      send_data bytes, type: content_type, disposition: "inline"
    end
end
