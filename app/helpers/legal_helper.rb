module LegalHelper
  # Details shown on /terms, /privacy and /refunds. Set LEGAL_JURISDICTION if the
  # governing law should be somewhere other than England and Wales.
  def legal_details
    {
      jurisdiction: ENV.fetch("LEGAL_JURISDICTION", "England and Wales"),
      updated: Date.new(2026, 9, 18)
    }
  end
end
