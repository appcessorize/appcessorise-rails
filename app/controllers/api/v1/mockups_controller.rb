module Api
  module V1
    class MockupsController < BaseController
      # POST /api/v1/mockups
      def create
        # Validate required parameters
        unless required_params_present?
          render json: {
            success: false,
            error: "Missing required parameters: affiliate_code, product_id, variant_id, image_url"
          }, status: :bad_request
          return
        end

        # Generate mockup via Printful
        printful_service = PrintfulService.new
        mockup_result = printful_service.generate_mockup(
          params[:image_url],
          params[:product_id],
          params[:variant_id]
        )

        unless mockup_result[:success]
          render json: {
            success: false,
            error: mockup_result[:error]
          }, status: :unprocessable_entity
          return
        end

        # Get product details
        product = PrintfulProduct.find_by(printful_product_id: params[:product_id])
        variant = find_variant(product, params[:variant_id]) if product

        # Calculate estimated shipping
        shipping_result = printful_service.calculate_shipping(
          { country: "US", state: "NY", city: "New York", zip: "10001" },
          [{ variant_id: params[:variant_id], quantity: 1 }]
        )

        estimated_shipping = shipping_result[:success] ? shipping_result.dig(:cheapest, "rate").to_f : 5.99

        # Create a temporary mockup record (stored in session or Redis in production)
        mockup_id = SecureRandom.uuid

        # Store mockup data temporarily (you'd want to use Redis in production)
        mockup_data = {
          mockup_id: mockup_id,
          affiliate_code: params[:affiliate_code],
          product_id: params[:product_id],
          variant_id: params[:variant_id],
          image_url: params[:image_url],
          mockup_image_url: mockup_result[:mockup_url],
          third_party_app_name: params[:third_party_app_name],
          third_party_order_id: params[:third_party_order_id],
          product_name: product&.name || "Custom Product",
          variant_name: variant_name(variant),
          base_price: product&.base_price || 29.99,
          estimated_shipping: estimated_shipping,
          created_at: Time.current
        }

        # In production, store this in Redis with expiration
        # For now, we'll return it and expect it to be passed back
        Rails.cache.write("mockup_#{mockup_id}", mockup_data, expires_in: 24.hours)

        render json: {
          success: true,
          data: {
            mockup_id: mockup_id,
            mockup_image_url: mockup_result[:mockup_url],
            original_image_url: params[:image_url],
            product_name: mockup_data[:product_name],
            variant_name: mockup_data[:variant_name],
            base_price: mockup_data[:base_price],
            estimated_shipping: estimated_shipping,
            checkout_url: checkout_url(mockup_id)
          }
        }, status: :created
      end

      private

      def required_params_present?
        params[:affiliate_code].present? &&
          params[:product_id].present? &&
          params[:variant_id].present? &&
          params[:image_url].present?
      end

      def find_variant(product, variant_id)
        return nil unless product&.variant_data

        product.variant_data.find { |v| v["id"] == variant_id.to_i }
      end

      def variant_name(variant)
        return "Standard" unless variant

        "#{variant['color']} / #{variant['size']}"
      end

      def checkout_url(mockup_id)
        Rails.application.routes.url_helpers.checkout_url(
          mockup_id,
          host: request.host_with_port,
          protocol: request.protocol.gsub("://", "")
        )
      end
    end
  end
end
