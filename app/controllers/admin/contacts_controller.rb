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

    def bulk_destroy
      ids = params[:ids]
      if ids.present?
        Contact.where(id: ids).destroy_all
        redirect_to admin_contacts_path, notice: "#{ids.size} contact(s) deleted."
      else
        redirect_to admin_contacts_path, alert: "No contacts selected."
      end
    end
  end
end
