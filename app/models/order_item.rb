class OrderItem < ApplicationRecord
  belongs_to :order

  validates :product_name, presence: true
  validates :price, presence: true, numericality: { greater_than: 0 }
  validates :quantity, presence: true, numericality: { only_integer: true, greater_than: 0 }

  # Calculate line item total
  def total
    price * quantity
  end
end
