class ProductsController < ApplicationController
  def index
    # The synced Printful catalog. Products with no variant data aren't
    # orderable, so they're hidden (see PrintfulProduct.active).
    @products = PrintfulProduct.active.by_price
  end

  def show
    @product_id = params[:id]
    @custom_text = params[:custom_text]
  end
end
