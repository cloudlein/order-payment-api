class Order < ApplicationRecord
  belongs_to :user
  has_many :order_items, dependent: :destroy
  has_one :payment, dependent: :destroy
  accepts_nested_attributes_for :order_items

  enum :status, { pending: "pending", processing: "processing", completed: "completed", cancelled: "cancelled" }

  before_create :calculate_total

  private

  def calculate_total
    self.total = order_items.sum(&:subtotal)
  end
end
