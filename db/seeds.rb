# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

# Create admin user
admin_email = ENV.fetch("ADMIN_EMAIL", "admin@appcessorise.com")
admin_password = ENV.fetch("ADMIN_PASSWORD", "changeme123")

User.find_or_create_by!(email: admin_email) do |user|
  user.password = admin_password
  user.password_confirmation = admin_password
  user.role = :admin
end

puts "✅ Admin user created: #{admin_email}"
