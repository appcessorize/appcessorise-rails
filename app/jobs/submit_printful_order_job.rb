# Submits a paid CustomOrder to Printful and creates the affiliate commission
# on success. Idempotent: skips orders already submitted.
#
# Called two ways by OrderCreationService:
#   - perform_now for the fast path (keeps printful_order_id in the API
#     response when Printful is up)
#   - perform_later as the retry path when the inline attempt fails, so a
#     Printful outage no longer leaves paid orders silently unfulfilled
class SubmitPrintfulOrderJob < ApplicationJob
  class SubmissionError < StandardError; end

  queue_as :default

  retry_on SubmissionError, wait: :polynomially_longer, attempts: 5 do |job, error|
    order = job.arguments.first
    order.update(printful_status: "submission_failed")
    Rails.logger.error "Printful submission permanently failed for order #{order.order_number}: #{error.message}"
  end

  discard_on ActiveJob::DeserializationError

  def perform(order)
    return if order.printful_order_id.present? # already submitted (idempotency)

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

    raise SubmissionError, result[:error].to_s unless result[:success]

    order.update(printful_order_id: result[:printful_order_id], printful_status: result[:status])
    create_affiliate_commission(order)
  end

  private

  def create_affiliate_commission(order)
    return if order.commission.present? # idempotency across retries

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
end
