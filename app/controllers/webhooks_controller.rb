class WebhooksController < ApplicationController
  skip_before_action :verify_authenticity_token

  # Printful renamed its webhook events in API v2 (shipment_sent etc.); the v1
  # names are still accepted so an old registration keeps working.
  PRINTFUL_EVENTS = {
    "shipment_sent" => :handle_package_shipped,
    "package_shipped" => :handle_package_shipped,
    "shipment_returned" => :handle_package_returned,
    "package_returned" => :handle_package_returned,
    "order_failed" => :handle_order_failed,
    "order_canceled" => :handle_order_canceled,
    "order_put_hold" => :handle_order_failed
  }.freeze

  def printful
    @raw_body = request.body.read
    request.body.rewind

    # Verify webhook signature
    unless verify_printful_signature
      render json: { error: "Invalid signature" }, status: :unauthorized
      return
    end

    # Parse webhook payload
    payload = JSON.parse(@raw_body)
    event_type = payload["type"]
    order_data = payload["data"]

    if (handler = PRINTFUL_EVENTS[event_type])
      send(handler, order_data)
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

  def stripe
    payload = request.body.read
    sig_header = request.headers["Stripe-Signature"]
    webhook_secret = ENV["STRIPE_WEBHOOK_SECRET"]

    begin
      event = Stripe::Webhook.construct_event(payload, sig_header, webhook_secret)
    rescue JSON::ParserError
      render json: { error: "Invalid JSON" }, status: :bad_request
      return
    rescue Stripe::SignatureVerificationError
      render json: { error: "Invalid signature" }, status: :unauthorized
      return
    end

    case event.type
    when "payment_intent.succeeded"
      handle_payment_succeeded(event.data.object)
    when "payment_intent.payment_failed"
      handle_payment_failed(event.data.object)
    when "charge.dispute.created"
      handle_dispute_created(event.data.object)
    when "charge.refunded"
      handle_charge_refunded(event.data.object)
    else
      Rails.logger.info "Unhandled Stripe webhook event: #{event.type}"
    end

    render json: { received: true }, status: :ok
  end

  private

  # --- Stripe handlers ---

  def handle_payment_succeeded(payment_intent)
    pi_id = payment_intent.id

    order = Order.find_by(stripe_payment_intent_id: pi_id)
    if order && order.status != "paid"
      order.update!(status: "paid")
      Rails.logger.info "Stripe webhook: Order ##{order.id} marked as paid"
    end

    custom_order = CustomOrder.find_by(stripe_payment_intent_id: pi_id)
    if custom_order && custom_order.payment_status != "paid"
      custom_order.update!(payment_status: "paid", paid_at: Time.current)
      Rails.logger.info "Stripe webhook: CustomOrder #{custom_order.order_number} marked as paid"
    end
  end

  def handle_payment_failed(payment_intent)
    pi_id = payment_intent.id

    order = Order.find_by(stripe_payment_intent_id: pi_id)
    if order && order.status == "pending"
      order.update!(status: "failed")
      Rails.logger.warn "Stripe webhook: Order ##{order.id} payment failed"
    end

    custom_order = CustomOrder.find_by(stripe_payment_intent_id: pi_id)
    if custom_order && custom_order.payment_status == "pending"
      custom_order.update!(payment_status: "failed")
      Rails.logger.warn "Stripe webhook: CustomOrder #{custom_order.order_number} payment failed"
    end
  end

  def handle_dispute_created(dispute)
    pi_id = dispute.payment_intent

    order = Order.find_by(stripe_payment_intent_id: pi_id)
    if order
      order.update!(status: "disputed")
      Rails.logger.warn "Stripe webhook: Order ##{order.id} disputed"
    end

    custom_order = CustomOrder.find_by(stripe_payment_intent_id: pi_id)
    if custom_order
      custom_order.update!(payment_status: "disputed")
      Rails.logger.warn "Stripe webhook: CustomOrder #{custom_order.order_number} disputed"
    end
  end

  def handle_charge_refunded(charge)
    pi_id = charge.payment_intent

    order = Order.find_by(stripe_payment_intent_id: pi_id)
    if order
      order.update!(status: "refunded")
      Rails.logger.info "Stripe webhook: Order ##{order.id} refunded"
    end

    custom_order = CustomOrder.find_by(stripe_payment_intent_id: pi_id)
    if custom_order
      custom_order.update!(payment_status: "refunded")
      Rails.logger.info "Stripe webhook: CustomOrder #{custom_order.order_number} refunded"
    end
  end

  # --- Printful handlers ---

  # Printful signs v2 webhooks with HMAC-SHA256 over the raw body and sends the
  # hex digest in x-pf-webhook-signature. The secret comes back from
  # POST /v2/webhooks (rake printful:register_webhook) as a hex string, so it
  # has to be decoded to raw bytes before being used as the HMAC key.
  def verify_printful_signature
    secret = ENV["PRINTFUL_WEBHOOK_SECRET"].to_s.strip
    signature = request.headers["x-pf-webhook-signature"].to_s

    if secret.blank?
      return true if Rails.env.development?
      Rails.logger.error "PRINTFUL_WEBHOOK_SECRET is not set — rejecting webhook"
      return false
    end

    return false if signature.blank?

    expected = OpenSSL::HMAC.hexdigest("SHA256", decoded_webhook_secret(secret), @raw_body)
    ActiveSupport::SecurityUtils.secure_compare(signature.downcase, expected)
  end

  def decoded_webhook_secret(secret)
    secret.match?(/\A(?:\h\h)+\z/) ? [ secret ].pack("H*") : secret
  end

  def handle_package_shipped(order_data)
    printful_order_id = order_data.dig("order", "id")
    return unless printful_order_id

    order = CustomOrder.find_by(printful_order_id: printful_order_id)
    return unless order

    # v1 sent an array of shipments, v2 sends a single shipment object.
    shipment = order_data["shipment"]
    shipment = shipment.first if shipment.is_a?(Array)
    tracking_number = shipment&.dig("tracking_number")
    tracking_url = shipment&.dig("tracking_url")

    order.update(
      printful_status: "shipped",
      printful_tracking_number: tracking_number,
      printful_tracking_url: tracking_url
    )

    OrderMailer.shipped(order).deliver_later
    Rails.logger.info "Order #{order.order_number} shipped: #{tracking_number}"
  end

  def handle_package_returned(order_data)
    printful_order_id = order_data.dig("order", "id")
    return unless printful_order_id

    order = CustomOrder.find_by(printful_order_id: printful_order_id)
    return unless order

    order.update(printful_status: "returned")

    refund_order(order)
    OrderMailer.returned(order).deliver_later
    Rails.logger.warn "Order #{order.order_number} returned — refund initiated"
  end

  def handle_order_failed(order_data)
    printful_order_id = order_data.dig("order", "id")
    return unless printful_order_id

    order = CustomOrder.find_by(printful_order_id: printful_order_id)
    return unless order

    order.update(printful_status: "failed")

    refund_order(order)
    OrderMailer.failed_admin(order).deliver_later
    Rails.logger.error "Order #{order.order_number} failed at Printful — refund initiated"
  end

  def handle_order_canceled(order_data)
    printful_order_id = order_data.dig("order", "id")
    return unless printful_order_id

    order = CustomOrder.find_by(printful_order_id: printful_order_id)
    return unless order

    order.update(printful_status: "canceled")

    refund_order(order)
    OrderMailer.canceled(order).deliver_later
    Rails.logger.info "Order #{order.order_number} canceled — refund initiated"
  end

  def refund_order(order)
    return unless order.payment_status == "paid" && order.stripe_payment_intent_id.present?

    Stripe::Refund.create(payment_intent: order.stripe_payment_intent_id)
    order.update(payment_status: "refunded")
    OrderMailer.refunded(order).deliver_later
    Rails.logger.info "Refund issued for order #{order.order_number}"
  rescue Stripe::StripeError => e
    Rails.logger.error "Refund failed for order #{order.order_number}: #{e.message}"
  end
end
