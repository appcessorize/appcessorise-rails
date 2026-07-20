module Api
  module V1
    class OrdersController < BaseController
      # POST /api/v1/orders
      # Auth (X-API-Key) is handled by BaseController; creation, payment
      # verification and Printful submission live in OrderCreationService,
      # shared with the web checkout's CheckoutsController#complete.
      def create
        result = OrderCreationService.new(
          mockup_id: params[:mockup_id],
          payment_intent_id: params[:payment_intent_id],
          shipping_address: params[:shipping_address] || {}
        ).call

        render json: result[:payload], status: result[:status]
      end
    end
  end
end
