class CustomOrder < ApplicationRecord
  # Associations
  belongs_to :user, optional: true
  has_one :affiliate_commission, dependent: :destroy

  # Validations
  validates :order_number, presence: true, uniqueness: true
  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :printful_product_id, presence: true
  validates :variant_id, presence: true
  validates :quantity, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :original_image_url, presence: true, format: { with: URI::DEFAULT_PARSER.make_regexp }
  validates :product_price, presence: true, numericality: { greater_than: 0 }
  validates :shipping_cost, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :total_price, presence: true, numericality: { greater_than: 0 }
  validates :recipient_name, :address_line1, :city, :state, :zip, :country, presence: true
  validates :payment_status, presence: true, inclusion: { in: %w[pending paid failed refunded] }

  # Callbacks
  before_validation :generate_order_number, on: :create
  before_validation :calculate_total_price

  # Scopes
  scope :pending_payment, -> { where(payment_status: "pending") }
  scope :paid, -> { where(payment_status: "paid") }
  scope :by_affiliate, ->(code) { where(affiliate_code: code) }
  scope :recent, -> { order(created_at: :desc) }

  private

  def generate_order_number
    return if order_number.present?

    loop do
      self.order_number = "ORD-#{Time.current.year}-#{SecureRandom.hex(4).upcase}"
      break unless CustomOrder.exists?(order_number: order_number)
    end
  end

  def calculate_total_price
    return unless product_price && shipping_cost

    self.total_price = product_price + shipping_cost
  end
end
