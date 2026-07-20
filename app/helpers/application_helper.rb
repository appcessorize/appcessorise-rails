module ApplicationHelper
  include Pagy::Frontend

  # The affiliate commission rate as display copy ("15%"). Single source of
  # truth for marketing pages so the number always matches what commissions
  # actually pay (DEFAULT_COMMISSION_RATE, used in SubmitPrintfulOrderJob).
  def commission_percent
    rate = ENV["DEFAULT_COMMISSION_RATE"]&.to_f || 0.15
    "#{(rate * 100).round}%"
  end
end
