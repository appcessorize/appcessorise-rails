class PrintfulProduct < ApplicationRecord
  # Validations
  validates :printful_product_id, presence: true, uniqueness: true
  validates :name, presence: true
  validates :base_price, presence: true, numericality: { greater_than: 0 }

  # Scopes
  scope :active, -> { where.not(variant_data: {}) }
  scope :by_price, ->(direction = :asc) { order(base_price: direction) }
end
