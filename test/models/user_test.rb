require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "a new user is assigned an api_key on create" do
    user = User.create!(email: "newkey@example.com", password: "Password123!", role: :affiliate)
    assert user.api_key.present?
    assert user.api_key.start_with?(User::API_KEY_PREFIX)
  end

  test "an explicitly provided api_key is not overwritten" do
    user = User.create!(email: "explicit@example.com", password: "Password123!", api_key: "ak_explicit_key")
    assert_equal "ak_explicit_key", user.api_key
  end

  test "find_by_api_key returns the matching user" do
    user = users(:two)
    assert_equal user, User.find_by_api_key(user.api_key)
  end

  test "find_by_api_key is blank-safe" do
    assert_nil User.find_by_api_key("")
    assert_nil User.find_by_api_key(nil)
  end

  test "generate_api_key! rotates to a new key" do
    user = users(:two)
    old_key = user.api_key
    user.generate_api_key!
    assert_not_equal old_key, user.reload.api_key
    assert user.api_key.start_with?(User::API_KEY_PREFIX)
  end

  test "new_api_key produces unique prefixed keys" do
    keys = Array.new(50) { User.new_api_key }
    assert_equal 50, keys.uniq.size
    assert keys.all? { |k| k.start_with?(User::API_KEY_PREFIX) }
  end

  test "affiliate_code derives from id for affiliates and admins" do
    assert_equal "AFF-#{users(:two).id.to_s.rjust(6, '0')}", users(:two).affiliate_code
    assert_equal "AFF-#{users(:admin).id.to_s.rjust(6, '0')}", users(:admin).affiliate_code
    assert_nil users(:one).affiliate_code
  end
end
