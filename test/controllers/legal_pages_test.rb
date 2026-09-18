require "test_helper"

class LegalPagesTest < ActionDispatch::IntegrationTest
  test "legal pages render and are linked from the footer" do
    { terms_path => "Terms of Service", privacy_path => "Privacy Policy", refunds_path => "Refunds" }.each do |path, heading|
      get path
      assert_response :success
      assert_select "h1", /#{heading}/
      assert_select "footer a[href=?]", terms_path
      assert_select "footer a[href=?]", privacy_path
      assert_select "footer a[href=?]", refunds_path
    end
  end

  test "cookie policy redirects into the privacy policy" do
    get "/cookies"
    assert_redirected_to "/privacy#cookies"
  end

  test "pages point at the contact form rather than an email address" do
    [ terms_path, privacy_path, refunds_path ].each do |path|
      get path
      assert_select "article a[href=?]", contact_path
      assert_no_match(/mailto:/, response.body)
    end
  end
end
