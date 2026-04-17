module Admin
  class AffiliateCommissionsController < BaseController
    def index
      @commissions = AffiliateCommission.order(created_at: :desc).includes(:user, :custom_order)
      @commissions = @commissions.where(status: params[:status]) if params[:status].present?

      @total_pending = AffiliateCommission.pending.sum(:commission_amount)
      @total_approved = AffiliateCommission.approved.sum(:commission_amount)
      @total_paid = AffiliateCommission.paid.sum(:commission_amount)
    end

    def approve
      commission = AffiliateCommission.find(params[:id])
      commission.approve!
      redirect_to admin_affiliate_commissions_path, notice: "Commission approved."
    end

    def pay
      commission = AffiliateCommission.find(params[:id])
      commission.mark_as_paid!
      redirect_to admin_affiliate_commissions_path, notice: "Commission marked as paid."
    end

    def bulk_approve
      AffiliateCommission.pending.where(id: params[:ids]).find_each(&:approve!)
      redirect_to admin_affiliate_commissions_path, notice: "Selected commissions approved."
    end

    def bulk_pay
      AffiliateCommission.approved.where(id: params[:ids]).find_each(&:mark_as_paid!)
      redirect_to admin_affiliate_commissions_path, notice: "Selected commissions marked as paid."
    end
  end
end
