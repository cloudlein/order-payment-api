require "securerandom"
class RefreshToken < ApplicationRecord
  belongs_to :user

  validates :token, presence: true, uniqueness: true
  validates :expires_at, presence: true

  scope :active, -> { where("expires_at > ? AND revoked_at IS NULL", Time.current) }

  def revoked?
    revoked_at.present?
  end

  def expired?
    expires_at.past?
  end

  def self.generate_for(user)
    create!(
      user: user,
      token: SecureRandom.hex(32),
      expires_at: 30.days.from_now
    )
  end

  def revoke!
    self.revoked_at = Time.current

    save!
  end
end
