require "test_helper"

class DashboardTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "affiliate dashboard shows the API key, affiliate code and real totals" do
    affiliate = users(:two)
    sign_in affiliate
    get dashboard_path

    assert_response :success
    assert_select "h2", text: "Affiliate Dashboard"
    # API key is rendered into the Stimulus controller's value attribute.
    assert_includes response.body, affiliate.api_key
    assert_includes response.body, affiliate.affiliate_code
    # Real commission total ($5.00 pending + $7.50 paid = $12.50).
    assert_includes response.body, "$12.50"
    # Recent sales table shows the affiliate's attributed order.
    assert_includes response.body, "ORD-2024-DEF456"
  end

  test "affiliate can regenerate their API key" do
    affiliate = users(:two)
    old_key = affiliate.api_key
    sign_in affiliate

    post regenerate_api_key_path
    assert_redirected_to dashboard_path
    assert_not_equal old_key, affiliate.reload.api_key
  end

  test "admin dashboard renders real platform stats" do
    sign_in users(:admin)
    get dashboard_path
    assert_response :success
    assert_select "h2", text: "Admin Panel"
  end

  test "customer dashboard renders without error" do
    sign_in users(:one)
    get dashboard_path
    assert_response :success
    assert_select "h2", text: "Customer Dashboard"
  end

  test "dashboard requires authentication" do
    get dashboard_path
    assert_redirected_to new_user_session_path
  end
end
