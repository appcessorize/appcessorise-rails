require "test_helper"

class PrintfulWebhookTest < ActionDispatch::IntegrationTest
  # Printful returns the secret as hex; the HMAC key is the decoded bytes.
  SECRET_HEX = "0123456789abcdef0123456789abcdef".freeze

  setup do
    @previous_secret = ENV["PRINTFUL_WEBHOOK_SECRET"]
    ENV["PRINTFUL_WEBHOOK_SECRET"] = SECRET_HEX
    @order = custom_orders(:one)
    @order.update!(printful_order_id: 999_001, printful_status: "pending")
  end

  teardown { ENV["PRINTFUL_WEBHOOK_SECRET"] = @previous_secret }

  def sign(body, secret_hex: SECRET_HEX)
    OpenSSL::HMAC.hexdigest("SHA256", [ secret_hex ].pack("H*"), body)
  end

  def shipment_event
    {
      type: "shipment_sent",
      occurred_at: "2026-09-18T10:00:00Z",
      store_id: 15_341_447,
      data: {
        order: { id: 999_001, status: "fulfilled" },
        shipment: { id: 5, tracking_number: "TRK123", tracking_url: "https://track.example/TRK123" }
      }
    }.to_json
  end

  test "accepts a correctly signed v2 shipment event and stores tracking" do
    body = shipment_event
    post "/webhooks/printful", params: body,
         headers: { "CONTENT_TYPE" => "application/json", "x-pf-webhook-signature" => sign(body) }

    assert_response :success
    @order.reload
    assert_equal "shipped", @order.printful_status
    assert_equal "TRK123", @order.printful_tracking_number
  end

  test "rejects a bad signature" do
    post "/webhooks/printful", params: shipment_event,
         headers: { "CONTENT_TYPE" => "application/json", "x-pf-webhook-signature" => "deadbeef" }

    assert_response :unauthorized
    assert_equal "pending", @order.reload.printful_status
  end

  test "rejects a missing signature" do
    post "/webhooks/printful", params: shipment_event, headers: { "CONTENT_TYPE" => "application/json" }
    assert_response :unauthorized
  end

  test "rejects a signature made with a different secret" do
    body = shipment_event
    post "/webhooks/printful", params: body,
         headers: { "CONTENT_TYPE" => "application/json",
                    "x-pf-webhook-signature" => sign(body, secret_hex: "ffffffffffffffffffffffffffffffff") }

    assert_response :unauthorized
  end

  test "still accepts the v1 event name and shipment array" do
    body = {
      type: "package_shipped",
      data: { order: { id: 999_001 }, shipment: [ { tracking_number: "OLD1", tracking_url: "https://t/OLD1" } ] }
    }.to_json

    post "/webhooks/printful", params: body,
         headers: { "CONTENT_TYPE" => "application/json", "x-pf-webhook-signature" => sign(body) }

    assert_response :success
    assert_equal "OLD1", @order.reload.printful_tracking_number
  end
end
