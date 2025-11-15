class ContactsController < ApplicationController
  before_action :authenticate_user!, only: [ :index ]
  before_action :require_admin, only: [ :index ]

  def new
    @contact = Contact.new
  end

  def create
    @contact = Contact.new(contact_params)

    if @contact.save
      redirect_to root_path, notice: "Thank you for contacting us! We'll get back to you soon."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def index
    @contacts = Contact.order(created_at: :desc)
  end

  private

  def contact_params
    params.require(:contact).permit(:email, :message)
  end

  def require_admin
    unless current_user&.admin?
      redirect_to root_path, alert: "You must be an admin to access this page."
    end
  end
end
