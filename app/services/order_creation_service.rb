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

    mockup_data = Rails.cache.read("mockup_#{@mockup_id}")
    return failure(:not_found, "Mockup not found or expired") unless mockup_data

    # Verify the payment actually happened before creating anything.
    # payment_intent_id is client-supplied and MUST NOT be trusted: without
    # this check anyone could submit fake ids and have real Printful orders
    # shipped for free.
    verification = verify_payment!(mockup_data)
    return failure(verification[:status], verification[:error]) unless verification[:ok]

    order = build_order(mockup_data, actual_shipping(mockup_data))
    return failure(:unprocessable_entity, order.errors.full_messages.join(", ")) unless order.save

    submit_to_printful(order)
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
  def build_order(mockup_data, shipping_cost)
    CustomOrder.new(
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

  def submit_to_printful(order)
    result = PrintfulService.new.create_order(
      variant_id: order.variant_id,
      quantity: order.quantity,
      original_image_url: order.original_image_url,
      product_price: order.product_price,
      shipping_cost: order.shipping_cost,
      total_price: order.total_price,
      shipping_address: {
        name: order.recipient_name,
        address1: order.address_line1,
        address2: order.address_line2,
        city: order.city,
        state: order.state,
        zip: order.zip,
        country: order.country
      }
    )

    if result[:success]
      order.update(printful_order_id: result[:printful_order_id], printful_status: result[:status])
      create_affiliate_commission(order)
    else
      Rails.logger.error "Printful order creation failed: #{result[:error]}"
      # Order is still saved but marked as needing manual review
    end
  end

  def create_affiliate_commission(order)
    # Prefer the affiliate account bound to the order at creation time
    # (authenticated key). Fall back to parsing the affiliate_code for
    # legacy shared-password orders that carry no user_id.
    user = affiliate_for_order(order)
    return unless user && (user.affiliate? || user.admin?)

    commission_rate = ENV["DEFAULT_COMMISSION_RATE"]&.to_f || 0.15
    commission_amount = order.product_price * commission_rate

    AffiliateCommission.create(
      user_id: user.id,
      custom_order_id: order.id,
      commission_amount: commission_amount,
      commission_rate: commission_rate,
      status: "pending"
    )

    order.update(affiliate_commission: commission_amount)
  end

  def affiliate_for_order(order)
    return order.user if order.user_id.present?
    return nil if order.affiliate_code.blank?

    user_id = order.affiliate_code.gsub("AFF-", "").to_i if order.affiliate_code.start_with?("AFF-")
    User.find_by(id: user_id) if user_id
  end

  def failure(status, error)
    { success: false, status: status, payload: { success: false, error: error } }
  end
end
