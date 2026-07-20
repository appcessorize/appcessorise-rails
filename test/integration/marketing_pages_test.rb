require "test_helper"

class MarketingPagesTest < ActionDispatch::IntegrationTest
  test "homepage shows the commission rate and integration snippet" do
    get root_path
    assert_response :success
    assert_includes response.body, "15% of every sale"
    assert_includes response.body, "Integrated in an afternoon"
    assert_includes response.body, "api/v1/mockups"
  end

  test "signup page sells the commission at the point of conversion" do
    get new_user_registration_path
    assert_response :success
    assert_includes response.body, "Start earning 15%"
    assert_includes response.body, "appcessorise"
  end

  test "products page lists orderable catalog products with API ids" do
    get products_path
    assert_response :success
    assert_includes response.body, "T-Shirt"          # active fixture
    assert_includes response.body, "123"              # its API product id
    assert_includes response.body, "You earn"
    assert_not_includes response.body, ">Mug<"        # empty variant_data => not orderable
  end

  test "products page shows an empty state when nothing is synced" do
    PrintfulProduct.delete_all
    get products_path
    assert_response :success
    assert_includes response.body, "Catalog is being stocked"
  end
end
