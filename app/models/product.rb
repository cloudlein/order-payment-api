class Product < ApplicationRecord
  belongs_to :product_category, optional: true

  # Validations
  validates :name, presence: true
  validates :price, presence: true, numericality: { greater_than: 0 }
  validates :stock, numericality: { greater_than_or_equal_to: 0, only_integer: true }

  # Scopes
  scope :by_category, ->(category_id) { where(product_category_id: category_id) }
  scope :in_stock, -> { where(Product.arel_table[:stock].gt(0)) }
end
