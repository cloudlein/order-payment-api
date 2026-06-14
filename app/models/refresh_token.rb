class RefreshToken < ApplicationRecord
  belongs_to :user

  validates :token, presence: true, uniqueness: true
  validates :expires_at, presence: true

  scope :active, -> { where("expires_at > ? AND revoked_at IS NULL", Time.current) }

  def revoked?
    revoked_at.present?
  end

  def expired?
    expires_at < Time.current
  end
end
