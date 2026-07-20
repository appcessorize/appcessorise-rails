class CreateMockups < ActiveRecord::Migration[8.1]
  # Mockups previously lived only in Rails.cache (24h TTL) between the
  # mockups API call and the orders API call. A cache eviction between the
  # customer paying and the order being created stranded a paid customer with
  # "Mockup not found". Persist them instead; also enables funnel analytics
  # (mockups created vs. converted to orders).
  def change
    create_table :mockups do |t|
      t.string :token, null: false                    # opaque id in the public API (was the cache key)
      t.bigint :user_id                               # affiliate who created it (nil for legacy shared-password callers)
      t.string :affiliate_code
      t.integer :printful_product_id, null: false
      t.integer :variant_id, null: false
      t.string :image_url, null: false
      t.string :mockup_image_url
      t.string :product_name
      t.string :variant_name
      t.decimal :base_price, precision: 10, scale: 2, null: false
      t.decimal :estimated_shipping, precision: 10, scale: 2, null: false
      t.string :third_party_app_name
      t.string :third_party_order_id
      t.datetime :expires_at, null: false
      t.datetime :consumed_at                         # set when an order is created from it
      t.timestamps

      t.index :token, unique: true
      t.index :user_id
      t.index [ :created_at, :consumed_at ], name: "index_mockups_funnel"
    end

    add_column :custom_orders, :mockup_id, :bigint
    add_index :custom_orders, :mockup_id
  end
end
