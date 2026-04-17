# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

# Create admin user (requires ADMIN_EMAIL and ADMIN_PASSWORD env vars)
if ENV["ADMIN_EMAIL"].present? && ENV["ADMIN_PASSWORD"].present?
  User.find_or_create_by!(email: ENV["ADMIN_EMAIL"]) do |user|
    user.password = ENV["ADMIN_PASSWORD"]
    user.password_confirmation = ENV["ADMIN_PASSWORD"]
    user.role = :admin
  end
  puts "Admin user created: #{ENV['ADMIN_EMAIL']}"
else
  puts "Skipping admin seed: set ADMIN_EMAIL and ADMIN_PASSWORD env vars"
end
