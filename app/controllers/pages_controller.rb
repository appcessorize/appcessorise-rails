class PagesController < ApplicationController
  # The pets landing page ships its own standalone CSS, so it opts out of
  # the Tailwind-based application layout.
  layout "pets", only: :pets

  def home
  end

  def pets
  end

  def about
  end

  def api_docs
  end
end
