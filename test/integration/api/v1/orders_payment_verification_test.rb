require "test_helper"
require "minitest/mock"

module Api
  module V1
    class OrdersPaymentVerificationTest < ActionDispatch::IntegrationTest
      # Fake Stripe PaymentIntent — shape-compatible with what the controller reads.
      FakeIntent = Struct.new(:id, :status, :metadata, :amount_received, keyword_init: true)

      class FakePrintful
        def calculate_shipping(*) = { success: true, cheapest: { "rate" => "5.99" } }
        def create_order(*) = { success: true, printful_order_id: 987_654, status: "draft" }
      end

      MOCKUP_ID = "test-mockup-uuid".freeze

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

      def order_params(intent_id: "pi_test_123")
        {
          mockup_id: MOCKUP_ID,
          payment_intent_id: intent_id,
          shipping_address: {
            name: "Test Buyer", email: "buyer@example.com",
            address1: "1 Main St", city: "New York", state: "NY",
            zip: "10001", country: "US"
          }
        }
      end

      def auth
        { "X-API-Key" => @affiliate.api_key }
      end

      # Quoted total: 19.99 + 5.99 = 25.98 -> 2598 cents
      def good_intent(id: "pi_test_123")
        FakeIntent.new(id: id, status: "succeeded",
                       metadata: { "mockup_id" => MOCKUP_ID }, amount_received: 2598)
      end

      def post_order(intent, params: order_params)
        retrieve = ->(_id) { intent.is_a?(Proc) ? intent.call : intent }
        Stripe::PaymentIntent.stub(:retrieve, retrieve) do
          PrintfulService.stub(:new, FakePrintful.new) do
            post "/api/v1/orders", params: params, headers: auth
          end
        end
      end

      test "a fake payment intent id is rejected with 402" do
        raiser = -> { raise Stripe::InvalidRequestError.new("No such payment_intent", "payment_intent") }
        post_order(raiser)
        assert_response :payment_required
        assert_equal "Payment not found", response.parsed_body["error"]
        assert_equal 0, CustomOrder.where(stripe_payment_intent_id: "pi_test_123").count
      end

      test "an unpaid intent is rejected with 402" do
        intent = good_intent
        intent.status = "requires_payment_method"
        post_order(intent)
        assert_response :payment_required
        assert_equal "Payment not completed", response.parsed_body["error"]
      end

      test "an intent paid for a different mockup is rejected with 402" do
        intent = good_intent
        intent.metadata = { "mockup_id" => "some-other-mockup" }
        post_order(intent)
        assert_response :payment_required
        assert_equal "Payment does not match this mockup", response.parsed_body["error"]
      end

      test "an underpaid intent is rejected with 402" do
        intent = good_intent
        intent.amount_received = 100
        post_order(intent)
        assert_response :payment_required
        assert_equal "Payment amount does not match order total", response.parsed_body["error"]
      end

      test "a payment intent already used by another order is rejected with 402" do
        CustomOrder.create!(
          email: "prior@example.com", printful_product_id: 71, variant_id: 4012,
          quantity: 1, original_image_url: "https://example.com/a.png",
          product_price: 19.99, shipping_cost: 5.99, total_price: 25.98,
          recipient_name: "Prior Buyer", address_line1: "2 Oak St", city: "LA",
          state: "CA", zip: "90001", country: "US",
          stripe_payment_intent_id: "pi_test_123", payment_status: "paid"
        )
        post_order(good_intent)
        assert_response :payment_required
        assert_equal "Payment already used for another order", response.parsed_body["error"]
      end

      test "stripe outage returns 503 rather than creating an unverified order" do
        raiser = -> { raise Stripe::APIConnectionError.new("connection failed") }
        post_order(raiser)
        assert_response :service_unavailable
        assert_equal 0, CustomOrder.where(stripe_payment_intent_id: "pi_test_123").count
      end

      test "a genuine succeeded payment for this mockup creates the order and commission" do
        assert_difference "CustomOrder.count", 1 do
          assert_difference "AffiliateCommission.count", 1 do
            post_order(good_intent)
          end
        end
        assert_response :created
        order = CustomOrder.find_by(stripe_payment_intent_id: "pi_test_123")
        assert_equal "paid", order.payment_status
        assert_equal @affiliate.id, order.user_id
        assert_equal 987_654, order.printful_order_id
      end
    end
  end
end
