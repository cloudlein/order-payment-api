class AddCategoryToProducts < ActiveRecord::Migration[8.1]
  def change
    add_reference :products, :product_category, null: true, foreign_key: true, index: true
  end
end
