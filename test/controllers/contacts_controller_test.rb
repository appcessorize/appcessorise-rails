require "test_helper"

class ContactsControllerTest < ActionDispatch::IntegrationTest
  test "should get contact form" do
    get contact_path
    assert_response :success
  end

  test "should create contact" do
    assert_difference("Contact.count", 1) do
      post contacts_path, params: {
        contact: {
          first_name: "Test",
          last_name: "User",
          email: "test@example.com",
          message: "Test message"
        }
      }
    end
    assert_redirected_to root_path
  end
end
