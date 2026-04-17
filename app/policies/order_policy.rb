class OrderPolicy < ApplicationPolicy
  def index?
    true
  end

  def show?
    record.user == user || user.admin?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      if user.admin?
        scope.all
      else
        scope.where(user: user)
      end
    end
  end
end
