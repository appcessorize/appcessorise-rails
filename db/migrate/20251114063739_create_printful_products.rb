class CreatePrintfulProducts < ActiveRecord::Migration[8.1]
  def change
    create_table :printful_products do |t|
      t.integer :printful_product_id, null: false
      t.string :name, null: false
      t.text :description
      t.decimal :base_price, precision: 10, scale: 2, null: false
      t.jsonb :variant_data, default: {}
      t.jsonb :mockup_template_ids, default: {}

      t.timestamps
    end

    add_index :printful_products, :printful_product_id, unique: true
  end
end
