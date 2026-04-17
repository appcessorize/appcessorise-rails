class OrderMailer < ApplicationMailer
  def shipped(custom_order)
    @order = custom_order
    mail(to: @order.email, subject: "Your order #{@order.order_number} has shipped!")
  end

  def returned(custom_order)
    @order = custom_order
    mail(to: @order.email, subject: "Update on your order #{@order.order_number}")
  end

  def failed_admin(custom_order)
    @order = custom_order
    mail(to: admin_email, subject: "Order #{@order.order_number} failed at Printful")
  end

  def canceled(custom_order)
    @order = custom_order
    mail(to: @order.email, subject: "Your order #{@order.order_number} has been canceled")
  end

  def refunded(custom_order)
    @order = custom_order
    mail(to: @order.email, subject: "Refund issued for order #{@order.order_number}")
  end

  private

  def admin_email
    ENV.fetch("ADMIN_EMAIL", "admin@appcessorise.com")
  end
end
