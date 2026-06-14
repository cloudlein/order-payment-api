class CreateProductCategories < ActiveRecord::Migration[8.1]
  def change
    create_table :product_categories do |t|
      t.string :name, null: false
      t.text :description
      t.references :parent, foreign_key: { to_table: :product_categories }, index: true

      t.timestamps
    end

    add_index :product_categories, :name, unique: true
  end
end
