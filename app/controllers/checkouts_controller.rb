class CheckoutsController < ApplicationController
  # No authentication required - allow guest checkout

  def new
    # Get product details from params (in a real app, fetch from database)
    @product_name = params[:product_name] || "Premium Phone Case"
    @product_price = params[:product_price]&.to_f || 29.99
    @quantity = params[:quantity]&.to_i || 1
    @amount = (@product_price * @quantity * 100).to_i # Convert to cents

    # Create Stripe PaymentIntent
    begin
      payment_metadata = {
        product_name: @product_name,
        quantity: @quantity
      }
      payment_metadata[:user_id] = current_user.id if user_signed_in?

      @payment_intent = Stripe::PaymentIntent.create({
        amount: @amount,
        currency: 'usd',
        metadata: payment_metadata
      })

      # Create pending order (user is optional for guest checkout)
      @order = Order.create!(
        user: current_user,
        amount: @product_price * @quantity,
        currency: 'usd',
        status: 'pending',
        stripe_payment_intent_id: @payment_intent.id
      )

      # Create order item
      @order.order_items.create!(
        product_name: @product_name,
        price: @product_price,
        quantity: @quantity
      )

    rescue Stripe::StripeError => e
      flash[:alert] = "Payment error: #{e.message}"
      redirect_to products_path
    end
  end

  def create
    # This endpoint is called after Stripe confirms payment on frontend
    payment_intent_id = params[:payment_intent_id]

    if payment_intent_id.present?
      order = Order.find_by(stripe_payment_intent_id: payment_intent_id)

      if order
        # Update order status
        order.update(status: 'paid')
        redirect_to success_checkout_path(order_id: order.id)
      else
        redirect_to failure_checkout_path
      end
    else
      redirect_to failure_checkout_path
    end
  end

  def success
    @order = Order.find_by(id: params[:order_id])
  end

  def failure
    flash.now[:alert] = "Payment failed. Please try again."
  end

  def mockup
    # Get mockup data from cache
    @mockup_data = Rails.cache.read("mockup_#{params[:mockup_id]}")

    unless @mockup_data
      flash[:alert] = "Mockup not found or has expired. Please generate a new mockup."
      redirect_to root_path
      return
    end

    # Calculate total amount
    @amount = ((@mockup_data[:base_price] + @mockup_data[:estimated_shipping]) * 100).to_i # Convert to cents

    # Create Stripe PaymentIntent
    begin
      @payment_intent = Stripe::PaymentIntent.create({
        amount: @amount,
        currency: 'usd',
        metadata: {
          mockup_id: params[:mockup_id],
          affiliate_code: @mockup_data[:affiliate_code],
          product_id: @mockup_data[:product_id],
          variant_id: @mockup_data[:variant_id]
        }
      })

      @client_secret = @payment_intent.client_secret
    rescue Stripe::StripeError => e
      flash[:alert] = "Payment error: #{e.message}"
      redirect_to root_path
    end
  end
end
