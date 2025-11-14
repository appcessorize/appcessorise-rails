class CreateCustomOrders < ActiveRecord::Migration[8.1]
  def change
    create_table :custom_orders do |t|
      t.string :order_number, null: false
      t.string :affiliate_code
      t.bigint :user_id
      t.string :email, null: false
      t.integer :printful_product_id, null: false
      t.integer :variant_id, null: false
      t.integer :quantity, default: 1, null: false
      t.string :original_image_url, null: false
      t.string :mockup_image_url
      t.decimal :product_price, precision: 10, scale: 2, null: false
      t.decimal :shipping_cost, precision: 10, scale: 2, null: false
      t.decimal :total_price, precision: 10, scale: 2, null: false
      t.decimal :affiliate_commission, precision: 10, scale: 2, default: 0.0
      t.integer :printful_order_id
      t.string :printful_status
      t.string :printful_tracking_number
      t.string :printful_tracking_url
      t.string :recipient_name, null: false
      t.string :address_line1, null: false
      t.string :address_line2
      t.string :city, null: false
      t.string :state, null: false
      t.string :zip, null: false
      t.string :country, default: "US", null: false
      t.string :phone
      t.string :stripe_payment_intent_id
      t.string :payment_status, default: "pending"
      t.datetime :paid_at
      t.string :third_party_app_name
      t.string :third_party_order_id
      t.text :notes

      t.timestamps
    end

    add_index :custom_orders, :order_number, unique: true
    add_index :custom_orders, :affiliate_code
    add_index :custom_orders, :user_id
    add_index :custom_orders, :payment_status
    add_index :custom_orders, :printful_status
  end
end
