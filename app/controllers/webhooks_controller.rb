class WebhooksController < ApplicationController
  skip_before_action :verify_authenticity_token

  def printful
    # Verify webhook signature
    unless verify_printful_signature
      render json: { error: "Invalid signature" }, status: :unauthorized
      return
    end

    # Parse webhook payload
    payload = JSON.parse(request.body.read)
    event_type = payload["type"]
    order_data = payload["data"]

    case event_type
    when "package_shipped"
      handle_package_shipped(order_data)
    when "package_returned"
      handle_package_returned(order_data)
    when "order_failed"
      handle_order_failed(order_data)
    when "order_canceled"
      handle_order_canceled(order_data)
    else
      Rails.logger.info "Unhandled Printful webhook event: #{event_type}"
    end

    render json: { received: true }, status: :ok
  rescue JSON::ParserError => e
    Rails.logger.error "Failed to parse Printful webhook: #{e.message}"
    render json: { error: "Invalid JSON" }, status: :bad_request
  rescue => e
    Rails.logger.error "Printful webhook error: #{e.message}"
    render json: { error: "Internal error" }, status: :internal_server_error
  end

  private

  def verify_printful_signature
    # Printful uses a webhook secret for verification
    # The secret is sent in the X-Printful-Signature header
    signature = request.headers["X-Printful-Signature"]
    webhook_secret = ENV["PRINTFUL_WEBHOOK_SECRET"]

    # In development, skip verification if no secret is set
    return true if Rails.env.development? && webhook_secret.blank?

    # Verify the signature matches
    # Printful uses HMAC SHA256
    expected_signature = OpenSSL::HMAC.hexdigest(
      OpenSSL::Digest.new('sha256'),
      webhook_secret,
      request.body.read
    )

    signature == expected_signature
  end

  def handle_package_shipped(order_data)
    printful_order_id = order_data.dig("order", "id")
    return unless printful_order_id

    order = CustomOrder.find_by(printful_order_id: printful_order_id)
    return unless order

    # Update order with tracking information
    shipments = order_data.dig("shipment") || []
    tracking_number = shipments.first&.dig("tracking_number")
    tracking_url = shipments.first&.dig("tracking_url")

    order.update(
      printful_status: "shipped",
      printful_tracking_number: tracking_number,
      printful_tracking_url: tracking_url
    )

    # TODO: Send email notification to customer
    Rails.logger.info "Order #{order.order_number} shipped: #{tracking_number}"
  end

  def handle_package_returned(order_data)
    printful_order_id = order_data.dig("order", "id")
    return unless printful_order_id

    order = CustomOrder.find_by(printful_order_id: printful_order_id)
    return unless order

    order.update(printful_status: "returned")

    # TODO: Handle refund logic
    Rails.logger.warn "Order #{order.order_number} returned"
  end

  def handle_order_failed(order_data)
    printful_order_id = order_data.dig("order", "id")
    return unless printful_order_id

    order = CustomOrder.find_by(printful_order_id: printful_order_id)
    return unless order

    order.update(printful_status: "failed")

    # TODO: Notify admin and possibly refund customer
    Rails.logger.error "Order #{order.order_number} failed at Printful"
  end

  def handle_order_canceled(order_data)
    printful_order_id = order_data.dig("order", "id")
    return unless printful_order_id

    order = CustomOrder.find_by(printful_order_id: printful_order_id)
    return unless order

    order.update(printful_status: "canceled")

    Rails.logger.info "Order #{order.order_number} canceled"
  end
end
