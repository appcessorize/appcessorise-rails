module Admin
  class OrdersController < BaseController
    def index
      scope = Order.order(created_at: :desc).includes(:user, :order_items)
      scope = scope.where(status: params[:status]) if params[:status].present?
      @pagy, @orders = pagy(scope, limit: 25)
    end

    def show
      @order = Order.find(params[:id])
    end
  end
end
