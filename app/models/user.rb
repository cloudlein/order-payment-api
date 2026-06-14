class User < ApplicationRecord
  has_secure_password

  has_many :refresh_tokens, dependent: :destroy
  has_many :orders, dependent: :destroy

  validates :name, presence: true
  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :role, presence: true

  enum :role, { user: "user", admin: "admin" }, default: "user"


  def generate_otp!
    self.otp_code = SecureRandom.random_number(100000..999999).to_s
    self.otp_expires_at = 5.minutes.from_now

    save!
  end

  def otp_valid?(code)
    otp_code.present? &&
      otp_expires_at.present? &&
      otp_code == code &&
      otp_expires_at > Time.current
  end


end
