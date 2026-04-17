module Admin
  class PrintfulProductsController < BaseController
    def index
      @products = PrintfulProduct.order(:name)
    end

    def show
      @product = PrintfulProduct.find(params[:id])
    end

    def sync
      PrintfulService.new.sync_products
      redirect_to admin_printful_products_path, notice: "Products synced from Printful."
    rescue => e
      redirect_to admin_printful_products_path, alert: "Sync failed: #{e.message}"
    end
  end
end
