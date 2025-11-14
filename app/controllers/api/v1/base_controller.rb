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
        parts = api_key.split("_")
        parts.last if parts.length > 1
      end

      def valid_api_key?(api_key)
        # Validate against environment variable password
        expected_password = ENV["API_PASSWORD"]

        if expected_password.blank?
          Rails.logger.error "API_PASSWORD not configured"
          return false
        end

        # Check if the API key starts with the correct password
        # Format: "password_AFF-000001" or just "password"
        parts = api_key.split("_")
        parts.first == expected_password
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
