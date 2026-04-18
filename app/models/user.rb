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

  def self.from_omniauth(auth)
    where(provider: auth.provider, uid: auth.uid).first_or_create do |user|
      user.email = auth.info.email
      user.password = Devise.friendly_token(32)
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
end
