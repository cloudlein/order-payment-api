class User < ApplicationRecord
  has_secure_password

  has_many :refresh_tokens, dependent: :destroy

  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :role, presence: true

  enum :role, { user: "user", admin: "admin" }, default: "user"
end
