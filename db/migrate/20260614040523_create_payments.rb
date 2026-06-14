class CreatePayments < ActiveRecord::Migration[8.1]
  def change
    create_table :payments do |t|
      t.references :order, null: false, foreign_key: true
      t.string :midtrans_transaction_id
      t.string :payment_type
      t.decimal :gross_amount, precision: 12, scale: 2
      t.string :status
      t.jsonb :raw_response, default: {}

      t.timestamps
    end
    add_index :payments, :midtrans_transaction_id, unique: true
  end
end
