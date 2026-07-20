require "test_helper"

# Exercises the real Devise flow (not the sign_in test helper) so the Devise 4->5
# upgrade is verified end to end: registration page, signup, and login.
class RegistrationFlowTest < ActionDispatch::IntegrationTest
  test "sign up and sign in pages render" do
    get new_user_registration_path
    assert_response :success
    get new_user_session_path
    assert_response :success
  end

  test "a real signup creates an affiliate with an API key and signs them in" do
    assert_difference "User.count", 1 do
      post user_registration_path, params: {
        user: { email: "flow_new@example.com", password: "Password123!", password_confirmation: "Password123!" }
      }
    end
    user = User.find_by(email: "flow_new@example.com")
    assert user.affiliate?, "new signup should default to affiliate"
    assert user.api_key.present?, "new signup should receive an API key"
    # Landed authenticated (Devise redirects after successful registration).
    assert_response :redirect
    follow_redirect!
    assert_response :success
  end

  test "an existing user can sign in through the real Devise flow" do
    User.create!(email: "flow_login@example.com", password: "Password123!", role: :affiliate)
    post user_session_path, params: {
      user: { email: "flow_login@example.com", password: "Password123!" }
    }
    assert_response :redirect

    # Authenticated session reaches a protected page.
    get dashboard_path
    assert_response :success
  end

  test "wrong password does not authenticate" do
    User.create!(email: "flow_bad@example.com", password: "Password123!", role: :affiliate)
    post user_session_path, params: {
      user: { email: "flow_bad@example.com", password: "wrong-password" }
    }
    get dashboard_path
    assert_redirected_to new_user_session_path
  end
end
