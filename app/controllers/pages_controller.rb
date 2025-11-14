class PagesController < ApplicationController
  def home
  end

  def about
  end

  def api_docs
    @api_password = ENV["API_PASSWORD"]
  end
end
