class Admin::UsersController < Admin::BaseController
  before_action :require_admin!
  before_action :set_user, only: %i[edit update toggle]

  def index
    @users = User.order(:username)
  end

  def new
    @user = User.new(role: "editor")
  end

  def create
    @user = User.new(user_params)
    if @user.save
      redirect_to admin_users_path, notice: "User \"#{@user.username}\" created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @user.update(update_params)
      redirect_to admin_users_path, notice: "User \"#{@user.username}\" updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def toggle
    if @user.update(active: !@user.active?)
      redirect_to admin_users_path, notice: "User #{@user.active? ? 'enabled' : 'disabled'}."
    else
      redirect_to admin_users_path, alert: @user.errors.full_messages.to_sentence
    end
  end

  private

  def set_user = @user = User.find(params[:id])

  def user_params
    params.require(:user).permit(:username, :email, :name, :role, :active, :password, :password_confirmation)
  end

  # On update, an untouched blank password field means "keep the current
  # password" rather than "clear it" (has_secure_password would otherwise
  # require a fresh, non-blank password on every save).
  def update_params
    permitted = user_params
    permitted = permitted.except(:password, :password_confirmation) if permitted[:password].blank?
    permitted
  end
end
