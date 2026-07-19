class DashboardController < ApplicationController
  before_action :authenticate_user!

  def index
    case current_user.role
    when "affiliate" then load_affiliate_stats
    when "admin"     then load_admin_stats
    else                  load_customer_stats
    end
  end

  # POST /dashboard/regenerate_api_key
  # Rotates the caller's key. Their old key stops working immediately, so this
  # doubles as "revoke a leaked key".
  def regenerate_api_key
    current_user.generate_api_key!
    redirect_to dashboard_path, notice: "Your API key has been regenerated. Update your integrations with the new key."
  end

  private

  def load_affiliate_stats
    sales = CustomOrder.where(user_id: current_user.id)
    @sales_count = sales.count
    @sales_this_month = sales.where(created_at: Time.current.beginning_of_month..Time.current).count
    @total_commissions = current_user.total_commissions
    @unpaid_commissions = current_user.unpaid_commissions
    @recent_sales = sales.recent.limit(10)
    @api_key = current_user.api_key
  end

  def load_admin_stats
    @total_users = User.count
    @total_products = PrintfulProduct.count
    @total_orders = CustomOrder.count
    @total_revenue = CustomOrder.paid.sum(:total_price)
    @api_key = current_user.api_key
  end

  def load_customer_stats
    orders = CustomOrder.where(email: current_user.email)
    @orders_count = orders.count
    @in_transit = orders.where(printful_status: %w[pending inprocess onhold partial]).count
    @total_spent = orders.paid.sum(:total_price)
  end
end
