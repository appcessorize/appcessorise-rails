# Next Steps

The core flow (API → mockup → checkout → Printful order → affiliate commission) is architecturally complete. The remaining work is operational.

## 1. OrdersController

Routes exist (`/orders`, `/orders/:id`) but no controller — these pages will 500.

- [ ] Create `OrdersController` with `index` and `show` actions
- [ ] `index` — list authenticated user's orders (both Order and CustomOrder)
- [ ] `show` — order detail with status, tracking info, and line items
- [ ] Add Pundit policies so users can only view their own orders
- [ ] Build views for order listing and detail pages

## 2. Stripe Webhooks

Payment confirmation is redirect-based only. If a user closes the tab before redirect, the order is never marked paid.

- [ ] Add `POST /webhooks/stripe` route
- [ ] Create `Webhooks::StripeController` (or extend existing `WebhooksController`)
- [ ] Verify webhook signature using `STRIPE_WEBHOOK_SECRET`
- [ ] Handle `payment_intent.succeeded` — mark Order/CustomOrder as paid
- [ ] Handle `payment_intent.payment_failed` — mark as failed
- [ ] Handle `charge.dispute.created` — flag order for review
- [ ] Handle `charge.refunded` — update payment status
- [ ] Register webhook endpoint in Stripe dashboard

## 3. Printful Webhook Email & Refund Logic

Webhook handler exists and verifies signatures, but event handling has TODO stubs.

- [ ] `package_shipped` — send shipping confirmation email with tracking link
- [ ] `package_returned` — notify customer and admin, flag for re-ship or refund
- [ ] `order_failed` — notify admin, trigger Stripe refund if already paid
- [ ] `order_canceled` — notify customer, trigger Stripe refund if already paid
- [ ] Wire up Resend mailer templates for each notification type

## 4. Admin Dashboard

Administrate gem is included but not fully wired up.

- [ ] Add admin namespace routes for all key models (Orders, CustomOrders, Users, AffiliateCommissions, PrintfulProducts, Contacts)
- [ ] Generate Administrate dashboards for each model
- [ ] Add affiliate commission approval/payout workflow in admin
- [ ] Add order status overview and filtering
- [ ] Lock down admin routes to `admin` role users only
