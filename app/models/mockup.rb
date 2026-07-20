class Mockup < ApplicationRecord
  TTL = 24.hours

  belongs_to :user, optional: true
  has_one :custom_order

  validates :token, presence: true, uniqueness: true
  validates :printful_product_id, :variant_id, :image_url, presence: true
  validates :base_price, :estimated_shipping, presence: true, numericality: { greater_than_or_equal_to: 0 }

  before_validation :assign_defaults, on: :create

  scope :usable, -> { where(consumed_at: nil).where(expires_at: Time.current..) }
  scope :consumed, -> { where.not(consumed_at: nil) }

  def usable?
    consumed_at.nil? && expires_at.future?
  end

  def consume!
    update!(consumed_at: Time.current)
  end

  # Data hash in the exact shape the cache-based flow used, so consumers
  # (OrderCreationService, checkout page) work identically for DB-backed and
  # legacy cached mockups.
  def to_data
    {
      mockup_id: token,
      affiliate_code: affiliate_code,
      affiliate_user_id: user_id,
      product_id: printful_product_id,
      variant_id: variant_id,
      image_url: image_url,
      mockup_image_url: mockup_image_url,
      product_name: product_name,
      variant_name: variant_name,
      base_price: base_price.to_f,
      estimated_shipping: estimated_shipping.to_f,
      third_party_app_name: third_party_app_name,
      third_party_order_id: third_party_order_id,
      created_at: created_at
    }
  end

  # Resolve a public mockup id to its data hash: DB first, then the legacy
  # cache entry (mockups created before the table existed remain valid for
  # their 24h TTL). Returns nil if unknown, expired, or already consumed.
  def self.data_for(token)
    usable.find_by(token: token)&.to_data || Rails.cache.read("mockup_#{token}")
  end

  private

  def assign_defaults
    self.token ||= SecureRandom.uuid
    self.expires_at ||= TTL.from_now
  end
end
