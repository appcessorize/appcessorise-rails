module Api
  module V1
    class OrdersController < BaseController
      # POST /api/v1/orders
      def create
        # Validate required parameters
        unless required_params_present?
          render json: {
            success: false,
            error: "Missing required parameters"
          }, status: :bad_request
          return
        end

        # Retrieve mockup data
        mockup_data = Rails.cache.read("mockup_#{params[:mockup_id]}")

        unless mockup_data
          render json: {
            success: false,
            error: "Mockup not found or expired"
          }, status: :not_found
          return
        end

        # Recalculate shipping for the actual address to prevent price manipulation
        printful_service = PrintfulService.new
        shipping_result = printful_service.calculate_shipping(
          {
            country: params.dig(:shipping_address, :country) || "US",
            state: params.dig(:shipping_address, :state),
            city: params.dig(:shipping_address, :city),
            zip: params.dig(:shipping_address, :zip)
          },
          [ { variant_id: mockup_data[:variant_id], quantity: 1 } ]
        )
        actual_shipping = shipping_result[:success] ? shipping_result.dig(:cheapest, "rate").to_f : mockup_data[:estimated_shipping]

        # Create order record.
        # user_id ties the sale to the affiliate account directly (set when the
        # mockup was created by an authenticated affiliate key), so commission
        # attribution doesn't depend on parsing the affiliate_code string.
        order = CustomOrder.new(
          affiliate_code: mockup_data[:affiliate_code],
          user_id: mockup_data[:affiliate_user_id],
          email: params.dig(:shipping_address, :email),
          printful_product_id: mockup_data[:product_id],
          variant_id: mockup_data[:variant_id],
          quantity: 1,
          original_image_url: mockup_data[:image_url],
          mockup_image_url: mockup_data[:mockup_image_url],
          product_price: mockup_data[:base_price],
          shipping_cost: actual_shipping,
          recipient_name: params.dig(:shipping_address, :name),
          address_line1: params.dig(:shipping_address, :address1),
          address_line2: params.dig(:shipping_address, :address2),
          city: params.dig(:shipping_address, :city),
          state: params.dig(:shipping_address, :state),
          zip: params.dig(:shipping_address, :zip),
          country: params.dig(:shipping_address, :country) || "US",
          phone: params.dig(:shipping_address, :phone),
          stripe_payment_intent_id: params[:payment_intent_id],
          payment_status: "paid",
          paid_at: Time.current,
          third_party_app_name: mockup_data[:third_party_app_name],
          third_party_order_id: mockup_data[:third_party_order_id]
        )

        unless order.save
          render json: {
            success: false,
            error: order.errors.full_messages.join(", ")
          }, status: :unprocessable_entity
          return
        end

        # Submit order to Printful
        printful_service = PrintfulService.new
        printful_result = printful_service.create_order(
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

        if printful_result[:success]
          order.update(
            printful_order_id: printful_result[:printful_order_id],
            printful_status: printful_result[:status]
          )

          # Create affiliate commission
          create_affiliate_commission(order)
        else
          Rails.logger.error "Printful order creation failed: #{printful_result[:error]}"
          # Order is still saved but marked as needing manual review
        end

        # Clear cached mockup data
        Rails.cache.delete("mockup_#{params[:mockup_id]}")

        render json: {
          success: true,
          order_number: order.order_number,
          printful_order_id: order.printful_order_id,
          estimated_delivery: (Time.current + 7.days).to_date,
          tracking_url: order.printful_tracking_url
        }, status: :created
      end

      private

      def required_params_present?
        params[:mockup_id].present? &&
          params[:payment_intent_id].present? &&
          params[:shipping_address].present?
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

        # Update order with commission amount
        order.update(affiliate_commission: commission_amount)
      end

      def affiliate_for_order(order)
        return order.user if order.user_id.present?
        return nil if order.affiliate_code.blank?

        user_id = extract_user_id_from_affiliate_code(order.affiliate_code)
        User.find_by(id: user_id) if user_id
      end

      def extract_user_id_from_affiliate_code(code)
        # Format: AFF-000001
        code.gsub("AFF-", "").to_i if code.start_with?("AFF-")
      end
    end
  end
end
