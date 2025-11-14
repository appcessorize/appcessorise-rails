class AffiliateCommission < ApplicationRecord
  # Associations
  belongs_to :user
  belongs_to :custom_order

  # Validations
  validates :commission_amount, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :commission_rate, presence: true, numericality: { greater_than: 0, less_than_or_equal_to: 1 }
  validates :status, presence: true, inclusion: { in: %w[pending approved paid] }

  # Scopes
  scope :pending, -> { where(status: "pending") }
  scope :approved, -> { where(status: "approved") }
  scope :paid, -> { where(status: "paid") }
  scope :for_user, ->(user_id) { where(user_id: user_id) }
  scope :unpaid, -> { where(status: ["pending", "approved"]) }

  # Class methods
  def self.total_for_user(user_id)
    for_user(user_id).sum(:commission_amount)
  end

  def self.unpaid_total_for_user(user_id)
    for_user(user_id).unpaid.sum(:commission_amount)
  end

  # Instance methods
  def mark_as_paid!
    update!(status: "paid", paid_at: Time.current)
  end

  def approve!
    update!(status: "approved")
  end
end
