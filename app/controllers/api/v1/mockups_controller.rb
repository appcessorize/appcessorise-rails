module Api
  module V1
    class MockupsController < BaseController
      # POST /api/v1/mockups
      def create
        # Attribution comes from the authenticated affiliate key when present, so
        # a caller cannot claim someone else's affiliate_code. The param is only
        # honoured for legacy shared-password callers that have no identity.
        affiliate_code = current_affiliate ? current_affiliate.affiliate_code : params[:affiliate_code]

        # Validate required parameters
        unless required_params_present?(affiliate_code)
          render json: {
            success: false,
            error: "Missing required parameters: product_id, variant_id, image_url"
          }, status: :bad_request
          return
        end

        # Validate image URL to prevent SSRF
        unless valid_image_url?(params[:image_url])
          render json: { success: false, error: "Invalid image URL. Must be a public http/https URL." }, status: :bad_request
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
          [ { variant_id: params[:variant_id], quantity: 1 } ]
        )

        estimated_shipping = shipping_result[:success] ? shipping_result.dig(:cheapest, "rate").to_f : 5.99

        # Persist the mockup. (Previously cache-only with a 24h TTL — a cache
        # eviction between payment and order creation stranded paid customers.)
        mockup = Mockup.create!(
          user_id: current_affiliate&.id,
          affiliate_code: affiliate_code,
          printful_product_id: params[:product_id],
          variant_id: params[:variant_id],
          image_url: params[:image_url],
          mockup_image_url: mockup_result[:mockup_url],
          third_party_app_name: params[:third_party_app_name],
          third_party_order_id: params[:third_party_order_id],
          product_name: product&.name || "Custom Product",
          variant_name: variant_name(variant),
          base_price: product&.base_price || 29.99,
          estimated_shipping: estimated_shipping
        )

        render json: {
          success: true,
          data: {
            mockup_id: mockup.token,
            mockup_image_url: mockup.mockup_image_url,
            original_image_url: mockup.image_url,
            product_name: mockup.product_name,
            variant_name: mockup.variant_name,
            base_price: mockup.base_price.to_f,
            estimated_shipping: mockup.estimated_shipping.to_f,
            checkout_url: checkout_url(mockup.token)
          }
        }, status: :created
      end

      private

      def required_params_present?(affiliate_code)
        affiliate_code.present? &&
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

      def valid_image_url?(url)
        uri = URI.parse(url)
        return false unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
        return false if uri.host.nil?
        # Block private/internal IPs
        return false if uri.host.match?(/\A(localhost|127\.|10\.|172\.(1[6-9]|2\d|3[01])\.|192\.168\.)/i)
        true
      rescue URI::InvalidURIError
        false
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
