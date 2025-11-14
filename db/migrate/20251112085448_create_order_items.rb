class CreateOrderItems < ActiveRecord::Migration[8.1]
  def change
    create_table :order_items do |t|
      t.references :order, null: false, foreign_key: true
      t.string :product_name, null: false
      t.decimal :price, precision: 10, scale: 2, null: false
      t.integer :quantity, default: 1, null: false
      t.text :metadata

      t.timestamps
    end
  end
end
