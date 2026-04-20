Rails.configuration.stripe = {
  publishable_key: ENV["STRIPE_PUBLISHABLE_KEY"],
  secret_key: ENV["STRIPE_SECRET_KEY"]
}

Stripe.api_key = Rails.configuration.stripe[:secret_key]

if Rails.env.production? && Stripe.api_key.blank?
  Rails.logger.warn "WARNING: STRIPE_SECRET_KEY is not set. Payments will not work."
end
