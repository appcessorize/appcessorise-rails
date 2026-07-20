# Creates a CustomOrder from a cached mockup + a verified Stripe payment, and
# submits it to Printful. Shared by:
#   - Api::V1::OrdersController (third-party affiliate apps, X-API-Key auth)
#   - CheckoutsController#complete (our own checkout page, CSRF-protected)
# so the web checkout no longer needs an API key embedded in its HTML.
#
# Returns { success:, status:, payload: } — payload is the JSON body to render.
class OrderCreationService
  def initialize(mockup_id:, payment_intent_id:, shipping_address:)
    @mockup_id = mockup_id
    @payment_intent_id = payment_intent_id
    @shipping = normalize(shipping_address)
  end

  def call
    return failure(:bad_request, "Missing required parameters") unless required_present?

    # DB-backed mockups are the norm; the cache read is a fallback for mockups
    # created before the mockups table existed (valid for their 24h TTL).
    mockup = Mockup.usable.find_by(token: @mockup_id)
    mockup_data = mockup&.to_data || Rails.cache.read("mockup_#{@mockup_id}")
    return failure(:not_found, "Mockup not found or expired") unless mockup_data

    # Verify the payment actually happened before creating anything.
    # payment_intent_id is client-supplied and MUST NOT be trusted: without
    # this check anyone could submit fake ids and have real Printful orders
    # shipped for free.
    verification = verify_payment!(mockup_data)
    return failure(verification[:status], verification[:error]) unless verification[:ok]

    order = build_order(mockup_data, actual_shipping(mockup_data), mockup)
    return failure(:unprocessable_entity, order.errors.full_messages.join(", ")) unless order.save

    submit_to_printful(order)
    mockup&.consume!
    Rails.cache.delete("mockup_#{@mockup_id}")

    {
      success: true,
      status: :created,
      payload: {
        success: true,
        order_number: order.order_number,
        printful_order_id: order.printful_order_id,
        estimated_delivery: (Time.current + 7.days).to_date,
        tracking_url: order.printful_tracking_url
      }
    }
  end

  private

  def normalize(shipping_address)
    hash = shipping_address.respond_to?(:to_unsafe_h) ? shipping_address.to_unsafe_h : shipping_address.to_h
    hash.symbolize_keys
  rescue NoMethodError
    {}
  end

  def required_present?
    @mockup_id.present? && @payment_intent_id.present? && @shipping.present?
  end

  # A payment is valid for this order only if ALL of these hold:
  #   1. The PaymentIntent exists on OUR Stripe account (callers cannot mint
  #      intents here — only checkouts#mockup does, server-side).
  #   2. It succeeded (money actually captured).
  #   3. Its metadata binds it to THIS mockup — an intent paid for a cheap
  #      product cannot be replayed against an expensive one.
  #   4. It covers the amount quoted when the intent was created
  #      (base price + estimated shipping) — belt and braces with 3.
  #   5. No other order has consumed it (replay protection; also enforced
  #      by a unique index + model validation).
  def verify_payment!(mockup_data)
    intent = Stripe::PaymentIntent.retrieve(@payment_intent_id)

    unless intent.status == "succeeded"
      return { ok: false, status: :payment_required, error: "Payment not completed" }
    end

    unless intent.metadata["mockup_id"] == @mockup_id
      return { ok: false, status: :payment_required, error: "Payment does not match this mockup" }
    end

    expected_cents = ((mockup_data[:base_price].to_f + mockup_data[:estimated_shipping].to_f) * 100).round
    if intent.amount_received < expected_cents
      return { ok: false, status: :payment_required, error: "Payment amount does not match order total" }
    end

    if CustomOrder.exists?(stripe_payment_intent_id: intent.id)
      return { ok: false, status: :payment_required, error: "Payment already used for another order" }
    end

    { ok: true }
  rescue Stripe::InvalidRequestError
    { ok: false, status: :payment_required, error: "Payment not found" }
  rescue Stripe::StripeError => e
    Rails.logger.error "Stripe verification error: #{e.message}"
    { ok: false, status: :service_unavailable, error: "Payment verification temporarily unavailable, please retry" }
  end

  # Recalculate shipping for the actual address to prevent price manipulation.
  def actual_shipping(mockup_data)
    result = PrintfulService.new.calculate_shipping(
      {
        country: @shipping[:country] || "US",
        state: @shipping[:state],
        city: @shipping[:city],
        zip: @shipping[:zip]
      },
      [ { variant_id: mockup_data[:variant_id], quantity: 1 } ]
    )
    result[:success] ? result.dig(:cheapest, "rate").to_f : mockup_data[:estimated_shipping]
  end

  # user_id ties the sale to the affiliate account directly (set when the
  # mockup was created by an authenticated affiliate key), so commission
  # attribution doesn't depend on parsing the affiliate_code string.
  def build_order(mockup_data, shipping_cost, mockup = nil)
    CustomOrder.new(
      mockup_id: mockup&.id,
      affiliate_code: mockup_data[:affiliate_code],
      user_id: mockup_data[:affiliate_user_id],
      email: @shipping[:email],
      printful_product_id: mockup_data[:product_id],
      variant_id: mockup_data[:variant_id],
      quantity: 1,
      original_image_url: mockup_data[:image_url],
      mockup_image_url: mockup_data[:mockup_image_url],
      product_price: mockup_data[:base_price],
      shipping_cost: shipping_cost,
      recipient_name: @shipping[:name],
      address_line1: @shipping[:address1],
      address_line2: @shipping[:address2],
      city: @shipping[:city],
      state: @shipping[:state],
      zip: @shipping[:zip],
      country: @shipping[:country] || "US",
      phone: @shipping[:phone],
      stripe_payment_intent_id: @payment_intent_id,
      payment_status: "paid",
      paid_at: Time.current,
      third_party_app_name: mockup_data[:third_party_app_name],
      third_party_order_id: mockup_data[:third_party_order_id]
    )
  end

  # Try Printful inline first so the API response includes printful_order_id
  # when Printful is up. If the inline attempt fails for ANY reason, hand the
  # order to the background job, which retries with backoff and flags the order
  # submission_failed if it ultimately can't — a paid order is never silently
  # left unfulfilled.
  def submit_to_printful(order)
    SubmitPrintfulOrderJob.perform_now(order)
  rescue StandardError => e
    Rails.logger.error "Inline Printful submission failed for #{order.order_number} (#{e.message}); queueing retry"
    order.update(printful_status: "submission_pending")
    SubmitPrintfulOrderJob.set(wait: 30.seconds).perform_later(order)
  end

  def failure(status, error)
    { success: false, status: status, payload: { success: false, error: error } }
  end
end
