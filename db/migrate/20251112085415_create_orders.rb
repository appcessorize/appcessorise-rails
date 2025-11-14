class CreateOrders < ActiveRecord::Migration[8.1]
  def change
    create_table :orders do |t|
      t.references :user, null: true, foreign_key: true
      t.references :affiliate, null: true, foreign_key: { to_table: :users }
      t.decimal :amount, precision: 10, scale: 2, null: false
      t.string :currency, default: "usd", null: false
      t.string :status, default: "pending", null: false
      t.string :stripe_payment_intent_id
      t.string :stripe_customer_id
      t.text :metadata

      t.timestamps
    end
  end
end
