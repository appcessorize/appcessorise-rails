class CreateAffiliateCommissions < ActiveRecord::Migration[8.1]
  def change
    create_table :affiliate_commissions do |t|
      t.bigint :user_id, null: false
      t.bigint :custom_order_id, null: false
      t.decimal :commission_amount, precision: 10, scale: 2, null: false
      t.decimal :commission_rate, precision: 5, scale: 4, null: false
      t.string :status, default: "pending", null: false
      t.datetime :paid_at

      t.timestamps
    end

    add_index :affiliate_commissions, :user_id
    add_index :affiliate_commissions, :custom_order_id
    add_index :affiliate_commissions, :status
    add_foreign_key :affiliate_commissions, :users
    add_foreign_key :affiliate_commissions, :custom_orders
  end
end
