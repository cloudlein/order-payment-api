class OrderItem < ApplicationRecord
  belongs_to :order
  belongs_to :product

  validates :quantity, presence: true, numericality: { greater_than: 0, only_integer: true }
  validates :price, presence: true, numericality: { greater_than: 0 }

  before_validation :copy_product_price

  def subtotal
    quantity + product.price
  end

  private

  def copy_product_price
    self.price ||= prodcut.price
  end
end
