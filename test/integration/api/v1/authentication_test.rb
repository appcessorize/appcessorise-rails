require "test_helper"
require "minitest/mock"

module Api
  module V1
    class AuthenticationTest < ActionDispatch::IntegrationTest
      # Minimal stand-in for PrintfulService so these tests exercise only the
      # auth/attribution layer, never the network.
      class FakePrintful
        def generate_mockup(*) = { success: true, mockup_url: "https://example.com/mockup.png" }
        def calculate_shipping(*) = { success: true, cheapest: { "rate" => "4.99" } }
      end

      setup do
        @affiliate = users(:two)
        # The controller caches mockup data; the test env uses :null_store, so
        # swap in a real store to assert on what gets written.
        @original_cache = Rails.cache
        Rails.cache = ActiveSupport::Cache::MemoryStore.new
      end

      teardown do
        Rails.cache = @original_cache
      end

      def mockup_params
        { product_id: 71, variant_id: 4012, image_url: "https://example.com/art.png" }
      end

      # --- Rejections: these fail auth before any Printful call, so no stub needed.

      test "request without an API key is rejected" do
        post "/api/v1/mockups", params: mockup_params
        assert_response :unauthorized
        assert_equal "Missing API key", response.parsed_body["error"]
      end

      test "request with an unknown key is rejected" do
        post "/api/v1/mockups", params: mockup_params, headers: auth("ak_not_a_real_key")
        assert_response :unauthorized
        assert_equal "Invalid API key", response.parsed_body["error"]
      end

      test "a customer key cannot authenticate to the affiliate API" do
        post "/api/v1/mockups", params: mockup_params, headers: auth(users(:one).api_key)
        assert_response :unauthorized
      end

      # --- Happy path + attribution.

      test "a valid affiliate key authenticates and attribution derives from the key" do
        mockup = post_mockup_and_find_record(auth(@affiliate.api_key), mockup_params)
        assert_response :created
        assert_equal @affiliate.affiliate_code, mockup.affiliate_code
        assert_equal @affiliate.id, mockup.user_id
      end

      test "a caller cannot spoof another affiliate's code via params" do
        mockup = post_mockup_and_find_record(
          auth(@affiliate.api_key),
          mockup_params.merge(affiliate_code: "AFF-999999")
        )
        assert_response :created
        assert_equal @affiliate.affiliate_code, mockup.affiliate_code
        assert_not_equal "AFF-999999", mockup.affiliate_code
      end

      private

      def auth(key)
        { "X-API-Key" => key }
      end

      def post_mockup_and_find_record(headers, params)
        PrintfulService.stub(:new, FakePrintful.new) do
          post "/api/v1/mockups", params: params, headers: headers
        end
        mockup_id = response.parsed_body.dig("data", "mockup_id")
        Mockup.find_by(token: mockup_id)
      end
    end
  end
end
