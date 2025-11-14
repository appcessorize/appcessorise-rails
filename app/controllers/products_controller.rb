class ProductsController < ApplicationController
  def index
  end

  def show
    @product_id = params[:id]
    @custom_text = params[:custom_text]
  end
end
