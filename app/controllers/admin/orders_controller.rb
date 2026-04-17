module Admin
  class OrdersController < BaseController
    def index
      @orders = Order.order(created_at: :desc).includes(:user, :order_items)
      @orders = @orders.where(status: params[:status]) if params[:status].present?
    end

    def show
      @order = Order.find(params[:id])
    end
  end
end
