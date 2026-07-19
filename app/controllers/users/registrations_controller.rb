class Users::RegistrationsController < Devise::RegistrationsController
  # Public sign-ups are affiliates: the whole point of an account is to
  # integrate and earn commissions. Customers buy through checkout without an
  # account, and admins are provisioned explicitly (seeds/console), so neither
  # goes through this path.
  #
  # Scoped to the registration path on purpose — we don't flip roles anywhere
  # else, so admin/console-created users keep whatever role they're given.
  def build_resource(hash = {})
    super
    resource.role ||= :affiliate
    resource.role = :affiliate if resource.role == "customer"
  end
end
