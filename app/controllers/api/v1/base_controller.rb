module Api
  module V1
    class BaseController < ApplicationController
      skip_before_action :verify_authenticity_token
      before_action :authenticate_api_key

      rescue_from ActiveRecord::RecordNotFound, with: :not_found
      rescue_from ActiveRecord::RecordInvalid, with: :unprocessable_entity

      # Set for requests authenticated with a per-affiliate key.
      attr_reader :current_affiliate

      private

      # Authentication resolves, in order:
      #   1. A per-affiliate key (X-API-Key: ak_...) — the preferred path. Sets
      #      @current_affiliate and derives @affiliate_code from it, so sales are
      #      attributed to the authenticated affiliate and cannot be spoofed.
      #   2. The legacy shared API_PASSWORD — kept as a transitional fallback
      #      so integrations shipped before per-affiliate keys keep working.
      #      Remove once all affiliates have migrated.
      #
      # INTERNAL_API_KEY support was removed 2026-07-20: its only consumer was
      # the checkout page, which embedded it in client-visible HTML (leaked).
      # The page now uses the CSRF-protected /checkout/complete endpoint.
      # Delete the INTERNAL_API_KEY env var — the leaked value must not stay valid.
      def authenticate_api_key
        api_key = request.headers["X-API-Key"]

        if api_key.blank?
          render json: { error: "Missing API key" }, status: :unauthorized
          return
        end

        return if authenticate_affiliate_key(api_key)
        return if authenticate_legacy_key(api_key)

        render json: { error: "Invalid API key" }, status: :unauthorized
      end

      # Preferred: unique per-affiliate key. Identifies the affiliate directly.
      def authenticate_affiliate_key(api_key)
        return false unless api_key.start_with?(User::API_KEY_PREFIX)

        user = User.find_by_api_key(api_key)
        return false unless user && (user.affiliate? || user.admin?)

        @current_affiliate = user
        @affiliate_code = user.affiliate_code
        true
      end

      # Legacy transitional path: shared password, optionally suffixed with an
      # affiliate code ("password_AFF-000001"). Attribution here is only as
      # trustworthy as the shared secret, which is why per-affiliate keys exist.
      def authenticate_legacy_key(api_key)
        expected_password = ENV["API_PASSWORD"]
        if expected_password.blank?
          Rails.logger.error "API_PASSWORD not configured"
          return false
        end

        password_part = if api_key.include?("_AFF-")
                          api_key.split("_AFF-").first
        else
                          api_key
        end

        return false unless ActiveSupport::SecurityUtils.secure_compare(password_part, expected_password)

        @affiliate_code = extract_affiliate_code(api_key)
        true
      end

      def extract_affiliate_code(api_key)
        match = api_key.match(/(AFF-\d+)/)
        match[1] if match
      end

      def not_found
        render json: { error: "Resource not found" }, status: :not_found
      end

      def unprocessable_entity(exception)
        render json: { error: exception.message }, status: :unprocessable_entity
      end
    end
  end
end
