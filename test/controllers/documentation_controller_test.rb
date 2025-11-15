require "test_helper"

class DocumentationControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get documentation_url
    assert_response :success
  end
end
