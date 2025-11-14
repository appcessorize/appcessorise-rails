# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2025_11_14_063803) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "affiliate_commissions", force: :cascade do |t|
    t.decimal "commission_amount", precision: 10, scale: 2, null: false
    t.decimal "commission_rate", precision: 5, scale: 4, null: false
    t.datetime "created_at", null: false
    t.bigint "custom_order_id", null: false
    t.datetime "paid_at"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["custom_order_id"], name: "index_affiliate_commissions_on_custom_order_id"
    t.index ["status"], name: "index_affiliate_commissions_on_status"
    t.index ["user_id"], name: "index_affiliate_commissions_on_user_id"
  end

  create_table "contacts", force: :cascade do |t|
    t.string "company"
    t.datetime "created_at", null: false
    t.string "email"
    t.string "first_name"
    t.string "last_name"
    t.text "message"
    t.string "phone"
    t.datetime "updated_at", null: false
  end

  create_table "custom_orders", force: :cascade do |t|
    t.string "address_line1", null: false
    t.string "address_line2"
    t.string "affiliate_code"
    t.decimal "affiliate_commission", precision: 10, scale: 2, default: "0.0"
    t.string "city", null: false
    t.string "country", default: "US", null: false
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.string "mockup_image_url"
    t.text "notes"
    t.string "order_number", null: false
    t.string "original_image_url", null: false
    t.datetime "paid_at"
    t.string "payment_status", default: "pending"
    t.string "phone"
    t.integer "printful_order_id"
    t.integer "printful_product_id", null: false
    t.string "printful_status"
    t.string "printful_tracking_number"
    t.string "printful_tracking_url"
    t.decimal "product_price", precision: 10, scale: 2, null: false
    t.integer "quantity", default: 1, null: false
    t.string "recipient_name", null: false
    t.decimal "shipping_cost", precision: 10, scale: 2, null: false
    t.string "state", null: false
    t.string "stripe_payment_intent_id"
    t.string "third_party_app_name"
    t.string "third_party_order_id"
    t.decimal "total_price", precision: 10, scale: 2, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.integer "variant_id", null: false
    t.string "zip", null: false
    t.index ["affiliate_code"], name: "index_custom_orders_on_affiliate_code"
    t.index ["order_number"], name: "index_custom_orders_on_order_number", unique: true
    t.index ["payment_status"], name: "index_custom_orders_on_payment_status"
    t.index ["printful_status"], name: "index_custom_orders_on_printful_status"
    t.index ["user_id"], name: "index_custom_orders_on_user_id"
  end

  create_table "order_items", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "metadata"
    t.bigint "order_id", null: false
    t.decimal "price", precision: 10, scale: 2, null: false
    t.string "product_name", null: false
    t.integer "quantity", default: 1, null: false
    t.datetime "updated_at", null: false
    t.index ["order_id"], name: "index_order_items_on_order_id"
  end

  create_table "orders", force: :cascade do |t|
    t.bigint "affiliate_id"
    t.decimal "amount", precision: 10, scale: 2, null: false
    t.datetime "created_at", null: false
    t.string "currency", default: "usd", null: false
    t.text "metadata"
    t.string "status", default: "pending", null: false
    t.string "stripe_customer_id"
    t.string "stripe_payment_intent_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["affiliate_id"], name: "index_orders_on_affiliate_id"
    t.index ["user_id"], name: "index_orders_on_user_id"
  end

  create_table "printful_products", force: :cascade do |t|
    t.decimal "base_price", precision: 10, scale: 2, null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.jsonb "mockup_template_ids", default: {}
    t.string "name", null: false
    t.integer "printful_product_id", null: false
    t.datetime "updated_at", null: false
    t.jsonb "variant_data", default: {}
    t.index ["printful_product_id"], name: "index_printful_products_on_printful_product_id", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.integer "role", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "affiliate_commissions", "custom_orders"
  add_foreign_key "affiliate_commissions", "users"
  add_foreign_key "order_items", "orders"
  add_foreign_key "orders", "users"
  add_foreign_key "orders", "users", column: "affiliate_id"
end
