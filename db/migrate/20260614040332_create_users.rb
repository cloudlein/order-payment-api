class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :email, null: false
      t.string :name
      t.string :otp_code
      t.datetime :otp_expires_at
      t.string :role, default: "user", null: false

      t.timestamps
    end
    add_index :users, :email, unique: true
  end
end
