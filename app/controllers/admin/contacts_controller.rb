module Admin
  class ContactsController < BaseController
    def index
      @contacts = Contact.order(created_at: :desc)
    end

    def show
      @contact = Contact.find(params[:id])
    end

    def destroy
      Contact.find(params[:id]).destroy
      redirect_to admin_contacts_path, notice: "Contact message deleted."
    end
  end
end
