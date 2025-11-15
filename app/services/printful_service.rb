class PrintfulService
  BASE_URL = "https://api.printful.com"
  API_VERSION = "v2"

  class PrintfulError < StandardError; end
  class RateLimitError < PrintfulError; end
  class AuthenticationError < PrintfulError; end

  def initialize
    @api_key = ENV["PRINTFUL_API_KEY"]
    @store_id = ENV["PRINTFUL_STORE_ID"]
    raise AuthenticationError, "Printful API key not configured" if @api_key.blank?
  end

  # Sync Printful catalog to our database
  def sync_products
    products = fetch_all_products
    synced_count = 0

    products.each do |product_data|
      product = PrintfulProduct.find_or_initialize_by(printful_product_id: product_data["id"])
      product.assign_attributes(
        name: product_data["title"],
        description: product_data["description"],
        base_price: calculate_base_price(product_data),
        variant_data: extract_variant_data(product_data),
        mockup_template_ids: extract_mockup_templates(product_data)
      )

      if product.save
        synced_count += 1
      else
        Rails.logger.error "Failed to sync product #{product_data['id']}: #{product.errors.full_messages.join(', ')}"
      end
    end

    { success: true, synced_count: synced_count, total_count: products.count }
  rescue => e
    Rails.logger.error "Failed to sync products: #{e.message}"
    { success: false, error: e.message }
  end

  # Generate mockup for a product with custom image
  def generate_mockup(image_url, product_id, variant_id)
    # Step 1: Create mockup generation task
    task_response = post("/mockup-generator/create-task/#{product_id}", {
      variant_ids: [ variant_id ],
      format: "jpg",
      options: [ "Front" ],
      option_groups: [ "Flat" ],
      files: [
        {
          placement: "front",
          image_url: image_url,
          position: {
            area_width: 1800,
            area_height: 2400,
            width: 1800,
            height: 1800,
            top: 300,
            left: 0
          }
        }
      ]
    })

    task_key = task_response.dig("result", "task_key")
    raise PrintfulError, "No task key returned" unless task_key

    # Step 2: Poll for mockup result
    mockup_url = poll_mockup_task(task_key)

    {
      success: true,
      mockup_url: mockup_url,
      task_key: task_key
    }
  rescue => e
    Rails.logger.error "Failed to generate mockup: #{e.message}"
    { success: false, error: e.message }
  end

  # Calculate shipping costs
  def calculate_shipping(address, items)
    response = post("/shipping/rates", {
      recipient: format_address(address),
      items: items.map { |item| format_item(item) }
    })

    rates = response.dig("result") || []
    cheapest_rate = rates.min_by { |rate| rate["rate"].to_f }

    {
      success: true,
      rates: rates,
      cheapest: cheapest_rate
    }
  rescue => e
    Rails.logger.error "Failed to calculate shipping: #{e.message}"
    { success: false, error: e.message }
  end

  # Create order with Printful
  def create_order(order_params)
    response = post("/orders", {
      recipient: format_address(order_params[:shipping_address]),
      items: [
        {
          variant_id: order_params[:variant_id],
          quantity: order_params[:quantity] || 1,
          files: [
            {
              url: order_params[:original_image_url]
            }
          ]
        }
      ],
      retail_costs: {
        currency: "USD",
        subtotal: order_params[:product_price].to_s,
        shipping: order_params[:shipping_cost].to_s,
        total: order_params[:total_price].to_s
      }
    })

    {
      success: true,
      printful_order_id: response.dig("result", "id"),
      status: response.dig("result", "status"),
      data: response["result"]
    }
  rescue => e
    Rails.logger.error "Failed to create order: #{e.message}"
    { success: false, error: e.message }
  end

  # Get order status from Printful
  def get_order_status(printful_order_id)
    response = get("/orders/#{printful_order_id}")

    {
      success: true,
      status: response.dig("result", "status"),
      shipments: response.dig("result", "shipments") || [],
      data: response["result"]
    }
  rescue => e
    Rails.logger.error "Failed to get order status: #{e.message}"
    { success: false, error: e.message }
  end

  private

  def fetch_all_products
    response = get("/store/products")
    response.dig("result") || []
  end

  def calculate_base_price(product_data)
    # Get the lowest variant price
    variants = product_data["variants"] || []
    return 0 if variants.empty?

    prices = variants.map { |v| v.dig("retail_price").to_f }
    prices.min || 0
  end

  def extract_variant_data(product_data)
    variants = product_data["variants"] || []
    variants.map do |variant|
      {
        id: variant["id"],
        name: variant["name"],
        size: variant["size"],
        color: variant["color"],
        color_code: variant["color_code"],
        price: variant["retail_price"],
        availability: variant["availability_status"]
      }
    end
  end

  def extract_mockup_templates(product_data)
    product_data.dig("mockup_templates") || []
  end

  def poll_mockup_task(task_key, max_attempts = 30, sleep_interval = 2)
    max_attempts.times do |attempt|
      response = get("/mockup-generator/task?task_key=#{task_key}")
      status = response.dig("result", "status")

      Rails.logger.info "Mockup task attempt #{attempt + 1}/#{max_attempts}: status=#{status}"

      case status
      when "completed"
        mockups = response.dig("result", "mockups") || []
        return mockups.first&.dig("mockup_url")
      when "failed"
        error_message = response.dig("result", "error") || "Unknown error"
        Rails.logger.error "Mockup generation failed: #{error_message}"
        Rails.logger.error "Full response: #{response.inspect}"
        raise PrintfulError, "Mockup generation failed: #{error_message}"
      else
        # Status is still "pending" or other
        sleep sleep_interval
      end
    end

    raise PrintfulError, "Mockup generation timed out after #{max_attempts * sleep_interval} seconds"
  end

  def format_address(address)
    {
      name: address[:name] || address[:recipient_name],
      address1: address[:address1] || address[:address_line1],
      address2: address[:address2] || address[:address_line2],
      city: address[:city],
      state_code: address[:state],
      country_code: address[:country] || "US",
      zip: address[:zip]
    }.compact
  end

  def format_item(item)
    {
      variant_id: item[:variant_id],
      quantity: item[:quantity] || 1
    }
  end

  # HTTP methods
  def get(path)
    make_request(:get, path)
  end

  def post(path, body = {})
    make_request(:post, path, body)
  end

  def make_request(method, path, body = nil)
    url = URI.join(BASE_URL, path)
    http = Net::HTTP.new(url.host, url.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_PEER # Enable SSL verification for security

    request = case method
    when :get
      Net::HTTP::Get.new(url)
    when :post
      Net::HTTP::Post.new(url)
    end

    request["Authorization"] = "Bearer #{@api_key}"
    request["Content-Type"] = "application/json"
    request["X-PF-Store-Id"] = @store_id if @store_id.present?
    request.body = body.to_json if body && method == :post

    response = http.request(request)

    case response.code.to_i
    when 200..299
      JSON.parse(response.body)
    when 429
      raise RateLimitError, "Rate limit exceeded"
    when 401, 403
      raise AuthenticationError, "Invalid API key"
    else
      error_message = JSON.parse(response.body)["error"]["message"] rescue response.body
      raise PrintfulError, "API request failed: #{error_message}"
    end
  rescue JSON::ParserError => e
    raise PrintfulError, "Invalid JSON response: #{e.message}"
  end
end
