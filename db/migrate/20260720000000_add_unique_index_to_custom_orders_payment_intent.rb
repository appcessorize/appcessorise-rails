class AddUniqueIndexToCustomOrdersPaymentIntent < ActiveRecord::Migration[8.1]
  # Backs the payment-replay protection in Api::V1::OrdersController: one
  # Stripe PaymentIntent can pay for at most one order. Partial index so
  # legacy rows with NULL intent ids are unaffected.
  def up
    duplicates = CustomOrder.where.not(stripe_payment_intent_id: nil)
                            .group(:stripe_payment_intent_id)
                            .having("COUNT(*) > 1")
                            .count
    if duplicates.any?
      raise "Cannot add unique index on custom_orders.stripe_payment_intent_id — " \
            "duplicate values exist for: #{duplicates.keys.join(', ')}. " \
            "Review these orders (possible replayed payments) and resolve manually, then re-run."
    end

    add_index :custom_orders, :stripe_payment_intent_id,
              unique: true,
              where: "stripe_payment_intent_id IS NOT NULL",
              name: "index_custom_orders_on_stripe_payment_intent_id_unique"
  end

  def down
    remove_index :custom_orders, name: "index_custom_orders_on_stripe_payment_intent_id_unique"
  end
end
