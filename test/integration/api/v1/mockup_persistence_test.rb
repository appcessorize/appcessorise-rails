require "test_helper"
require "minitest/mock"

module Api
  module V1
    class MockupPersistenceTest < ActionDispatch::IntegrationTest
      FakeIntent = Struct.new(:id, :status, :metadata, :amount_received, keyword_init: true)

      class FakePrintful
        def calculate_shipping(*) = { success: true, cheapest: { "rate" => "5.99" } }
        def create_order(*) = { success: true, printful_order_id: 42, status: "draft" }
      end

      setup do
        @affiliate = users(:two)
        @mockup = Mockup.create!(
          user_id: @affiliate.id,
          affiliate_code: @affiliate.affiliate_code,
          printful_product_id: 71,
          variant_id: 4012,
          image_url: "https://example.com/art.png",
          mockup_image_url: "https://example.com/mockup.png",
          product_name: "Test Tee",
          base_price: 19.99,
          estimated_shipping: 5.99
        )
      end

      def order_params(intent_id)
        {
          mockup_id: @mockup.token,
          payment_intent_id: intent_id,
          shipping_address: {
            name: "Buyer", email: "b@example.com", address1: "1 St",
            city: "NYC", state: "NY", zip: "10001", country: "US"
          }
        }
      end

      def intent_for(id)
        FakeIntent.new(id: id, status: "succeeded",
                       metadata: { "mockup_id" => @mockup.token }, amount_received: 2598)
      end

      def post_order(intent_id)
        Stripe::PaymentIntent.stub(:retrieve, ->(_id) { intent_for(intent_id) }) do
          PrintfulService.stub(:new, FakePrintful.new) do
            post "/api/v1/orders", params: order_params(intent_id),
                                   headers: { "X-API-Key" => @affiliate.api_key }
          end
        end
      end

      test "an order created from a DB mockup consumes it and links it" do
        post_order("pi_db_1")
        assert_response :created
        order = CustomOrder.find_by(stripe_payment_intent_id: "pi_db_1")
        assert_equal @mockup.id, order.mockup_id
        assert @mockup.reload.consumed_at.present?, "mockup should be consumed"
      end

      test "a consumed mockup cannot be ordered again" do
        @mockup.consume!
        post_order("pi_db_2")
        assert_response :not_found
        assert_equal "Mockup not found or expired", response.parsed_body["error"]
      end

      test "an expired mockup cannot be ordered" do
        @mockup.update!(expires_at: 1.minute.ago)
        post_order("pi_db_3")
        assert_response :not_found
      end

      test "mockup model defaults and scopes behave" do
        assert @mockup.token.present?
        assert @mockup.usable?
        assert_includes Mockup.usable, @mockup
        @mockup.consume!
        assert_not @mockup.usable?
        assert_not_includes Mockup.usable, @mockup
      end
    end
  end
end
