class Order < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :affiliate, class_name: "User", optional: true
  has_many :order_items, dependent: :destroy

  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :currency, presence: true
  validates :status, presence: true, inclusion: { in: %w[pending processing paid failed refunded cancelled completed] }

  # Calculate affiliate commission (10% example)
  def affiliate_commission
    return 0 unless affiliate.present?
    amount * 0.10
  end

  # Calculate total from order items
  def calculate_total
    order_items.sum { |item| item.price * item.quantity }
  end
end
