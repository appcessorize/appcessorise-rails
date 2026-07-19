class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable, :lockable,
         :omniauthable, omniauth_providers: [:google_oauth2]

  # Associations
  has_many :custom_orders, dependent: :nullify
  has_many :affiliate_commissions, dependent: :destroy

  enum :role, { customer: 0, affiliate: 1, admin: 2 }

  # API key lifecycle
  # Affiliates (and admins) authenticate to the public API with a unique,
  # per-user key sent in the X-API-Key header. The key both authenticates the
  # request and identifies which affiliate the resulting sale belongs to.
  API_KEY_PREFIX = "ak_".freeze

  before_create :ensure_api_key

  def self.find_by_api_key(key)
    return nil if key.blank?

    find_by(api_key: key)
  end

  def generate_api_key!
    update!(api_key: self.class.new_api_key)
  end

  def self.new_api_key
    "#{API_KEY_PREFIX}#{SecureRandom.hex(24)}"
  end

  def self.from_omniauth(auth)
    where(provider: auth.provider, uid: auth.uid).first_or_create do |user|
      user.email = auth.info.email
      user.password = Devise.friendly_token(32)
      user.role = :affiliate
    end
  end

  # Instance methods
  def affiliate_code
    return nil unless affiliate? || admin?

    "AFF-#{id.to_s.rjust(6, '0')}"
  end

  def total_commissions
    affiliate_commissions.sum(:commission_amount)
  end

  def unpaid_commissions
    affiliate_commissions.unpaid.sum(:commission_amount)
  end

  private

  # Every user gets an API key at creation so the credential exists the moment
  # an affiliate signs up — no separate "activate API" step required.
  def ensure_api_key
    self.api_key ||= self.class.new_api_key
  end
end
