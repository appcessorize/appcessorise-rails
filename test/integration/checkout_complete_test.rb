require "test_helper"
require "minitest/mock"

class CheckoutCompleteTest < ActionDispatch::IntegrationTest
  FakeIntent = Struct.new(:id, :status, :metadata, :amount_received, :client_secret, keyword_init: true)

  class FakePrintful
    def calculate_shipping(*) = { success: true, cheapest: { "rate" => "5.99" } }
    def create_order(*) = { success: true, printful_order_id: 555_111, status: "draft" }
  end

  MOCKUP_ID = "web-checkout-mockup".freeze

  setup do
    @affiliate = users(:two)
    @original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    Rails.cache.write("mockup_#{MOCKUP_ID}", {
      mockup_id: MOCKUP_ID,
      affiliate_code: @affiliate.affiliate_code,
      affiliate_user_id: @affiliate.id,
      product_id: 71,
      variant_id: 4012,
      image_url: "https://example.com/art.png",
      mockup_image_url: "https://example.com/mockup.png",
      product_name: "Test Tee",
      base_price: 19.99,
      estimated_shipping: 5.99,
      created_at: Time.current
    })
  end

  teardown do
    Rails.cache = @original_cache
  end

  def order_params
    {
      mockup_id: MOCKUP_ID,
      payment_intent_id: "pi_web_123",
      shipping_address: {
        name: "Web Buyer", email: "web@example.com",
        address1: "1 Main St", city: "New York", state: "NY",
        zip: "10001", country: "US"
      }
    }
  end

  def good_intent
    FakeIntent.new(id: "pi_web_123", status: "succeeded",
                   metadata: { "mockup_id" => MOCKUP_ID }, amount_received: 2598)
  end

  test "checkout page completes an order without any API key" do
    Stripe::PaymentIntent.stub(:retrieve, ->(_id) { good_intent }) do
      PrintfulService.stub(:new, FakePrintful.new) do
        # No X-API-Key header — this is the whole point of the endpoint.
        post "/checkout/complete", params: order_params, as: :json
      end
    end
    assert_response :created
    assert response.parsed_body["success"]
    order = CustomOrder.find_by(stripe_payment_intent_id: "pi_web_123")
    assert_equal @affiliate.id, order.user_id
    assert_equal 555_111, order.printful_order_id
  end

  test "web completion is still gated by payment verification" do
    raiser = ->(_id) { raise Stripe::InvalidRequestError.new("No such payment_intent", "payment_intent") }
    Stripe::PaymentIntent.stub(:retrieve, raiser) do
      post "/checkout/complete", params: order_params, as: :json
    end
    assert_response :payment_required
    assert_equal "Payment not found", response.parsed_body["error"]
  end

  test "the checkout page no longer embeds an API key in its HTML" do
    intent = good_intent
    intent.client_secret = "pi_web_123_secret_test"
    Stripe::PaymentIntent.stub(:create, ->(_args) { intent }) do
      get "/checkout/#{MOCKUP_ID}"
    end
    assert_response :success
    assert_not_includes response.body, "X-API-Key", "checkout page must not reference API keys"
    assert_includes response.body, "/checkout/complete"
    assert_includes response.body, "X-CSRF-Token"
  end
end
