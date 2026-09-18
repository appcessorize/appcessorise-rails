require "net/http"
require "json"

namespace :printful do
  BASE = "https://api.printful.com".freeze

  def pf_request(method, path, body = nil)
    uri = URI("#{BASE}#{path}")
    klass = { get: Net::HTTP::Get, post: Net::HTTP::Post, delete: Net::HTTP::Delete }.fetch(method)
    req = klass.new(uri)
    req["Authorization"] = "Bearer #{ENV['PRINTFUL_API_KEY']}"
    req["Content-Type"] = "application/json"
    req["X-PF-Store-Id"] = ENV["PRINTFUL_STORE_ID"] if ENV["PRINTFUL_STORE_ID"].present?
    req.body = body.to_json if body

    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
    [ res.code.to_i, (JSON.parse(res.body) rescue { "raw" => res.body }) ]
  end

  def pf_check(label, method, path, body = nil)
    code, data = pf_request(method, path, body)
    ok = code.between?(200, 299)
    puts "#{ok ? '  ok ' : ' FAIL'}  #{label.ljust(28)} #{code}"
    puts "        #{data.to_json[0, 300]}" unless ok
    [ ok, data ]
  end

  desc "Check the Printful token and the endpoints we depend on"
  task smoke: :environment do
    abort "PRINTFUL_API_KEY is not set" if ENV["PRINTFUL_API_KEY"].blank?
    puts "Printful smoke test (store #{ENV['PRINTFUL_STORE_ID']})"

    ok, stores = pf_check("token / stores", :get, "/v2/stores")
    abort "Token is not working — fix that first." unless ok
    puts "        store: #{stores.dig('data', 0, 'name')} (id #{stores.dig('data', 0, 'id')})"

    pf_check("catalog products", :get, "/v2/catalog-products?limit=1")
    pf_check("catalog product 71", :get, "/products/71")
    pf_check("store products", :get, "/store/products")
    pf_check("orders", :get, "/v2/orders?limit=1")
    _, hooks = pf_check("webhook config", :get, "/v2/webhooks")
    puts "        webhook url: #{hooks.dig('data', 'default_url') || '(none registered)'}"
    puts "        expires_at:  #{hooks.dig('data', 'expires_at') || '(never)'}"
    puts "        events:      #{Array(hooks.dig('data', 'events')).map { |e| e['type'] }.join(', ').presence || '(none)'}"
  end

  desc "Register the webhook URL with Printful. URL=https://appcessorise.com/webhooks/printful"
  task register_webhook: :environment do
    url = ENV["URL"].presence || abort("Pass URL=https://your-domain/webhooks/printful")
    abort "URL must be https" unless url.start_with?("https://")

    events = %w[shipment_sent shipment_returned order_failed order_canceled]
    code, data = pf_request(:post, "/v2/webhooks", {
      default_url: url,
      events: events.map { |type| { type: type } }
    })

    unless code.between?(200, 299)
      abort "Registration failed (#{code}): #{data.to_json[0, 500]}"
    end

    secret = data.dig("result", "secret_key") || data.dig("data", "secret_key")
    public_key = data.dig("result", "public_key") || data.dig("data", "public_key")

    puts "Registered #{url} for: #{events.join(', ')}"
    puts "public key: #{public_key}"
    puts
    puts "Set this in .env and in production, then redeploy:"
    puts "PRINTFUL_WEBHOOK_SECRET=#{secret}"
    puts
    puts "It is shown once. Verification fails until it is deployed."
  end

  desc "Show the current webhook configuration"
  task webhook_status: :environment do
    _, data = pf_request(:get, "/v2/webhooks")
    puts JSON.pretty_generate(data)
  end
end
