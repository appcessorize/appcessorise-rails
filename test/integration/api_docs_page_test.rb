require "test_helper"

class ApiDocsPageTest < ActionDispatch::IntegrationTest
  test "api docs page renders with the per-key integration guidance" do
    get api_docs_path
    assert_response :success
    assert_includes response.body, "X-API-Key"
    assert_includes response.body, "ak_your_key"
    # The quick-start snippets are present.
    assert_includes response.body, "URLSession"        # Swift/iOS
    assert_includes response.body, "await fetch"        # JavaScript/web
    # No leftover shared-password / appended-affiliate-code guidance.
    assert_not_includes response.body, "YOUR_API_KEY_AFF-"
  end
end
