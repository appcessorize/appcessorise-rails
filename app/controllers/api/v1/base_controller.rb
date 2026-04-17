module Api
  module V1
    class BaseController < ApplicationController
      skip_before_action :verify_authenticity_token
      before_action :authenticate_api_key

      rescue_from ActiveRecord::RecordNotFound, with: :not_found
      rescue_from ActiveRecord::RecordInvalid, with: :unprocessable_entity

      private

      def authenticate_api_key
        api_key = request.headers["X-API-Key"]

        if api_key.blank?
          render json: { error: "Missing API key" }, status: :unauthorized
          return
        end

        unless valid_api_key?(api_key)
          render json: { error: "Invalid API key" }, status: :unauthorized
          return
        end

        # Extract affiliate code from API key
        # Format: "API_PASSWORD_affiliate_code"
        @affiliate_code = extract_affiliate_code(api_key)
      end

      def extract_affiliate_code(api_key)
        # Extract affiliate code after the password
        # Format: "password_AFF-000001"
        match = api_key.match(/(AFF-\d+)/)
        match[1] if match
      end

      def valid_api_key?(api_key)
        # Allow internal requests using a separate internal key
        internal_key = ENV["INTERNAL_API_KEY"]
        return true if internal_key.present? && ActiveSupport::SecurityUtils.secure_compare(api_key, internal_key)

        # Validate against environment variable password
        expected_password = ENV["API_PASSWORD"]

        if expected_password.blank?
          Rails.logger.error "API_PASSWORD not configured"
          return false
        end

        # Format: "password_AFF-000001" or just "password"
        # Split on the first underscore that precedes "AFF-" to avoid splitting the password itself
        password_part = if api_key.include?("_AFF-")
                          api_key.split("_AFF-").first
                        else
                          api_key
                        end

        ActiveSupport::SecurityUtils.secure_compare(password_part, expected_password)
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
