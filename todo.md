# TODO

## Priority 1 — Core Product
- [ ] Per-user API keys (api_keys table, unique key per affiliate, replaces shared API_PASSWORD)
- [ ] Default role → affiliate on signup
- [ ] Affiliate dashboard with real data (commissions, referrals, API key display/regenerate)

## Priority 2 — Incomplete Features
- [ ] Products page — controller is empty, decide if showing Printful products or just a landing page
- [ ] Customer dashboard — wire up real order/spend data instead of hardcoded zeros
- [ ] Admin dashboard stats — admin section of user dashboard shows hardcoded zeros

## Priority 3 — Nice-to-Haves
- [ ] Email confirmation (enable Devise :confirmable)
- [ ] Verify password reset emails work end-to-end with Resend
- [ ] Test Printful product sync end-to-end
- [ ] Solid Queue worker — ensure deliver_later emails are actually processed (may need worker process in Dockerfile)
