module Admin
  class CustomOrdersController < BaseController
    def index
      @custom_orders = CustomOrder.order(created_at: :desc)
      @custom_orders = @custom_orders.where(payment_status: params[:status]) if params[:status].present?
    end

    def show
      @custom_order = CustomOrder.find(params[:id])
    end
  end
end
