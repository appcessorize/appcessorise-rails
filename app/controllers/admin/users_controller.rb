module Admin
  class UsersController < BaseController
    def index
      scope = User.order(created_at: :desc)
      scope = scope.where(role: params[:role]) if params[:role].present?
      @pagy, @users = pagy(scope, limit: 25)
    end

    def show
      @user = User.find(params[:id])
    end

    def update
      @user = User.find(params[:id])
      if @user.update(user_params)
        redirect_to admin_user_path(@user), notice: "User updated."
      else
        render :show, status: :unprocessable_entity
      end
    end

    private

    def user_params
      params.require(:user).permit(:role)
    end
  end
end
