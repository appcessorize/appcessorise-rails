class OrdersController < ApplicationController
  before_action :authenticate_user!

  def index
    @orders = policy_scope(Order).order(created_at: :desc).includes(:order_items)
    @custom_orders = CustomOrder.where(user: current_user).recent
  end

  def show
    @order = Order.find_by(id: params[:id])

    if @order
      authorize @order
      @order_items = @order.order_items
    else
      @custom_order = CustomOrder.find_by(id: params[:id])
      if @custom_order
        authorize @custom_order, policy_class: OrderPolicy
      else
        redirect_to orders_path, alert: "Order not found."
      end
    end
  end
end
