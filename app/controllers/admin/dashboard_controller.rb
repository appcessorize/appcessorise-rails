module Admin
  class DashboardController < BaseController
    def index
      @total_revenue = Order.where(status: "paid").sum(:amount) +
                       CustomOrder.where(payment_status: "paid").sum(:total_price)
      @orders_count = Order.count
      @custom_orders_count = CustomOrder.count
      @users_count = User.count
      @pending_commissions = AffiliateCommission.unpaid.sum(:commission_amount)

      @recent_orders = Order.order(created_at: :desc).limit(5).includes(:user, :order_items)
      @recent_custom_orders = CustomOrder.order(created_at: :desc).limit(5)
    end
  end
end
