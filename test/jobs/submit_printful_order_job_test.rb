require "test_helper"
require "minitest/mock"

class SubmitPrintfulOrderJobTest < ActiveJob::TestCase
  class FailingPrintful
    def create_order(*) = { success: false, error: "printful is down" }
  end

  class WorkingPrintful
    def create_order(*) = { success: true, printful_order_id: 777, status: "draft" }
  end

  setup do
    @affiliate = users(:two)
    @order = CustomOrder.create!(
      user_id: @affiliate.id,
      affiliate_code: @affiliate.affiliate_code,
      email: "job@example.com", printful_product_id: 71, variant_id: 4012,
      quantity: 1, original_image_url: "https://example.com/a.png",
      product_price: 20.00, shipping_cost: 5.00, total_price: 25.00,
      recipient_name: "Job Buyer", address_line1: "1 St", city: "NYC",
      state: "NY", zip: "10001", country: "US",
      stripe_payment_intent_id: "pi_job_#{SecureRandom.hex(4)}", payment_status: "paid"
    )
  end

  test "success records printful id and creates the commission" do
    PrintfulService.stub(:new, WorkingPrintful.new) do
      SubmitPrintfulOrderJob.perform_now(@order)
    end
    @order.reload
    assert_equal 777, @order.printful_order_id
    assert @order.commission.present?
    assert_equal 3.00.to_d, @order.commission.commission_amount # 15% of 20.00
    assert_equal 3.00.to_d, @order.affiliate_commission
  end

  test "is idempotent when the order was already submitted" do
    @order.update!(printful_order_id: 111)
    PrintfulService.stub(:new, WorkingPrintful.new) do
      SubmitPrintfulOrderJob.perform_now(@order)
    end
    assert_equal 111, @order.reload.printful_order_id
    assert_nil @order.commission
  end

  test "does not duplicate a commission across retries" do
    AffiliateCommission.create!(
      user: @affiliate, custom_order: @order,
      commission_amount: 3.00, commission_rate: 0.15, status: "pending"
    )
    PrintfulService.stub(:new, WorkingPrintful.new) do
      SubmitPrintfulOrderJob.perform_now(@order)
    end
    assert_equal 1, AffiliateCommission.where(custom_order_id: @order.id).count
  end

  test "a failed submission schedules a retry" do
    PrintfulService.stub(:new, FailingPrintful.new) do
      assert_enqueued_with(job: SubmitPrintfulOrderJob) do
        SubmitPrintfulOrderJob.perform_now(@order)
      end
    end
    assert_nil @order.reload.printful_order_id
  end

  test "exhausted retries mark the order submission_failed instead of losing it" do
    job = SubmitPrintfulOrderJob.new(@order)
    # retry_on tracks attempts per exception class, not via #executions
    job.exception_executions = { "[SubmitPrintfulOrderJob::SubmissionError]" => 5 }
    PrintfulService.stub(:new, FailingPrintful.new) do
      job.perform_now
    end
    assert_equal "submission_failed", @order.reload.printful_status
    assert_nil @order.printful_order_id
  end
end
