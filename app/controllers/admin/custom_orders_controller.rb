module Admin
  class CustomOrdersController < BaseController
    def index
      scope = CustomOrder.order(created_at: :desc)
      scope = scope.where(payment_status: params[:status]) if params[:status].present?
      @pagy, @custom_orders = pagy(scope, limit: 25)
    end

    def show
      @custom_order = CustomOrder.find(params[:id])
    end
  end
end
