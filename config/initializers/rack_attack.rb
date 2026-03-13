# frozen_string_literal: true

class Rack::Attack
  # Throttle login attempts: 5 requests per 20 seconds per IP
  throttle("logins/ip", limit: 5, period: 20.seconds) do |req|
    req.ip if req.path == "/users/sign_in" && req.post?
  end

  # Throttle general API requests: 30 requests per minute per IP
  throttle("api/ip", limit: 30, period: 1.minute) do |req|
    req.ip if req.path.start_with?("/api/v1/")
  end

  # Tighter throttle on mockup generation (calls external Printful API)
  throttle("api/mockups/ip", limit: 10, period: 1.minute) do |req|
    req.ip if req.path == "/api/v1/mockups" && req.post?
  end

  # Return appropriate response format
  self.throttled_responder = lambda do |request|
    match_data = request.env["rack.attack.match_data"]
    now = match_data[:epoch_time]
    retry_after = match_data[:period] - (now % match_data[:period])

    if request.path.start_with?("/api/")
      [
        429,
        { "Content-Type" => "application/json", "Retry-After" => retry_after.to_s },
        [{ error: "Rate limit exceeded. Retry in #{retry_after} seconds." }.to_json]
      ]
    else
      [
        429,
        { "Content-Type" => "text/html", "Retry-After" => retry_after.to_s },
        ["<html><body><h1>Too Many Requests</h1><p>Please retry in #{retry_after} seconds.</p></body></html>"]
      ]
    end
  end

  # Safelist localhost in development
  safelist("allow-localhost") do |req|
    req.ip == "127.0.0.1" || req.ip == "::1" if Rails.env.development?
  end
end
