class ProductCategory < ApplicationRecord
  # Self-referential association untuk sub-kategori
  belongs_to :parent, class_name: "ProductCategory", optional: true
  has_many :children, class_name: "ProductCategory", foreign_key: :parent_id, dependent: :nullify

  # Relasi ke products
  has_many :products, dependent: :nullify

  # Validations
  validates :name, presence: true, uniqueness: { case_sensitive: false }
  validates :description, length: { maximum: 1000 }, allow_blank: true

  # Scopes
  scope :roots, -> { where(parent_id: nil) }
  scope :ordered, -> { order(:name) }
end
