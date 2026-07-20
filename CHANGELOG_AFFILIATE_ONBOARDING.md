# Affiliate Onboarding — Change Log

Branch: `affiliate-onboarding`
Goal: let affiliates sign up, integrate into their iOS/web app easily, add products, and track sales.

This document records every change made in this effort, why, and its migration/deploy implications. Newest section at the bottom.

---

## Context: state before this work

- API auth used a single shared `API_PASSWORD` for **all** affiliates. Affiliates hand-built a fragile credential string (`password_AFF-000001`).
- `affiliate_code` was passed as a plain request parameter, separate from auth — spoofable, so any caller could claim any affiliate's sales.
- `users` had no `api_key` column. New signups defaulted to `customer`.
- Sales/commission machinery (Printful orders, `AffiliateCommission`) was already built and working.

## Plan (5 steps)

1. Per-affiliate API keys — `X-API-Key` authenticates *and* identifies the affiliate. Shared `API_PASSWORD` kept as a transitional fallback.
2. Default new signups to `affiliate` + auto-generate an API key.
3. Affiliate dashboard: show/copy/regenerate key, integration snippet, real sales & commission totals.
4. Tighten attribution: commission + mockup affiliate derived from the authenticated key, not a param.
5. Update `/api-docs` for a genuinely easy integration.

---

## Changes

### Step 1 — Per-affiliate API keys ✅

**What changed**

- `db/migrate/20260719000000_add_api_key_to_users.rb` — adds `users.api_key` (string) with a unique index.
- `db/migrate/20260719000001_backfill_user_api_keys.rb` — gives every pre-existing user a key. Idempotent (only fills `NULL`); `down` is a deliberate no-op (keys are credentials, not derived data).
- `app/models/user.rb`
  - `API_KEY_PREFIX = "ak_"`.
  - `before_create :ensure_api_key` — every user gets a key the moment they're created, so an affiliate can integrate immediately after signup with no "activate API" step.
  - `User.new_api_key` → `ak_` + 24 random bytes hex. `User.find_by_api_key(key)` (blank-safe). `#generate_api_key!` for regeneration.
- `app/controllers/api/v1/base_controller.rb` — auth now resolves in order:
  1. **Per-affiliate key** (`X-API-Key: ak_...`): looks up the user, confirms they're an affiliate/admin, sets `@current_affiliate` and derives `@affiliate_code` from it. Sales attribution is now bound to the authenticated key and **cannot be spoofed**.
  2. **Legacy shared `API_PASSWORD` / `INTERNAL_API_KEY`**: unchanged behaviour, kept as a transitional fallback so integrations shipped before per-affiliate keys keep working.

**Why:** the shared password blocked self-serve onboarding, couldn't be revoked per affiliate, and leaked the moment it shipped inside anyone's app. Per-affiliate keys are the linchpin for "sign up → integrate → track sales."

**Deploy notes**
- Two migrations to run on deploy. Backfill is safe to re-run.
- No breaking change: legacy `API_PASSWORD` still works during the transition. Remove that fallback (and the `_AFF-` param format) once all affiliates have moved to `ak_` keys.

**Verified:** console check — key auto-generated on create, correct prefix, `find_by_api_key` round-trips, blank → nil, regenerate rotates the key, zero users left without a key.

### Step 2 — Default new signups to affiliate ✅

**What changed**

- `app/controllers/users/registrations_controller.rb` (new) — `Users::RegistrationsController` overrides `build_resource` to default a new signup's role to `affiliate`.
- `config/routes.rb` — `devise_for` now routes `registrations` to the custom controller (alongside the existing omniauth one).
- `app/models/user.rb` — `from_omniauth` sets `user.role = :affiliate` for new Google signups.

**Why:** an account only exists so someone can integrate and earn commissions. Customers check out without an account; admins are provisioned explicitly. So every self-serve signup should land as an affiliate, ready to grab a key and integrate.

**Scoping / safety:** the role default lives only on the public registration + OAuth-signup paths. `User.new` (admin, console, seeds) is untouched and still defaults to `customer` at the DB level — no existing users are reclassified.

**Deploy notes:** no migration. Behaviour-only change to the signup path.

**Verified:** console check — plain `User.new` stays `customer`; registration path → `affiliate`; Google OAuth new user → `affiliate` and receives an API key; registration routes resolve to `users/registrations`.

### Step 4 — Tighten sales attribution ✅

_(Done before Step 3 because it pairs directly with the auth work in Step 1.)_

**What changed**

- `app/controllers/api/v1/mockups_controller.rb`
  - `affiliate_code` now comes from `current_affiliate.affiliate_code` when a per-affiliate key authenticated the request; the `affiliate_code` **param is ignored** in that case. It's only honoured for legacy shared-password callers that have no identity.
  - The cached mockup now also stores `affiliate_user_id` (the authenticated affiliate's id).
  - `required_params_present?` takes the resolved code, so authenticated affiliates no longer need to send `affiliate_code` at all.
- `app/controllers/api/v1/orders_controller.rb`
  - The created `CustomOrder` sets `user_id` from `mockup_data[:affiliate_user_id]`, binding the sale to the affiliate account.
  - New `affiliate_for_order` resolves the affiliate from `order.user` first, falling back to parsing `affiliate_code` only for legacy orders — commission attribution no longer depends on string-parsing.

**Why:** previously any caller holding the shared password could send `affiliate_code: "AFF-<someone-else>"` and steal another affiliate's commission. Now attribution is bound to the authenticated key.

**Tests added**

- `test/integration/api/v1/authentication_test.rb` (new) — missing key → 401, unknown key → 401, customer key → 401, valid affiliate key → 201 with attribution derived from the key, and a spoofed `affiliate_code` param is ignored. Uses pure Minitest `stub` for Printful (no new gem) and a real `MemoryStore` cache for the assertions.
- `test/models/user_test.rb` — API key lifecycle (auto-generate, no-overwrite, lookup, blank-safe, rotate, uniqueness) + `affiliate_code` derivation.
- `test/fixtures/users.yml` — fixture users given `api_key` values.

**Deploy notes:** no migration. Existing legacy integrations keep working via the fallback path. Full suite green (16 runs, 0 failures).

### Step 3 — Affiliate dashboard with real data ✅

**What changed**

- `app/controllers/dashboard_controller.rb` — `index` now loads real per-role data:
  - **Affiliate:** attributed sales count, sales this month, total & unpaid commissions, 10 most-recent sales, and the API key.
  - **Admin:** total users, products, orders, and paid revenue (replaces hardcoded `0`/`3`/`$0`).
  - **Customer:** their order count, in-transit count, and total spent (matched by email).
  - New `regenerate_api_key` action (`POST /dashboard/regenerate_api_key`) rotates the key — also serves as "revoke a leaked key," since the old one stops working immediately.
- `config/routes.rb` — added the `regenerate_api_key` route.
- `app/views/dashboard/index.html.erb`
  - Affiliate section: real stat tiles; **new API Key card** (reveal/mask, copy-to-clipboard with feedback, regenerate with confirm, link to docs) showing the affiliate code; **Recent Sales** table (order #, date, status, sale total, commission) with an empty state.
  - Admin & customer sections: hardcoded numbers replaced with the real values. Removed the untracked "Rewards Points" tile.
- `app/javascript/controllers/api_key_controller.js` (new) + registered in `controllers/index.js` — Stimulus controller for reveal/mask + copy. Copy uses the existing clipboard pattern; masking shows `ak_xxx…last4`.

**Bug fixed along the way (pre-existing, production-affecting)**

`CustomOrder` declared `has_one :affiliate_commission` **and** has an `affiliate_commission` decimal column. The association shadowed the column's accessors, so:
- `POST /api/v1/orders` raised `ActiveRecord::AssociationTypeMismatch` on `order.update(affiliate_commission: amount)` — the order API **500'd** after the order/commission were already created.
- `app/views/admin/custom_orders/show.html.erb` called `sprintf("%.2f", @custom_order.affiliate_commission)` on the association (nil/record), which errors.

**Fix:** renamed the association to `has_one :commission, class_name: "AffiliateCommission"` (`app/models/custom_order.rb`). The FK is unchanged (`custom_order_id`), so no migration. The `affiliate_commission` column reader/writer now works everywhere — order API, admin show page, and the new dashboard all read the correct decimal.

**Tests added**

- `test/integration/dashboard_test.rb` — affiliate dashboard shows API key + affiliate code + real `$12.50` commission total + attributed order; key regeneration rotates the key; admin/customer dashboards render; unauthenticated → redirect to sign-in.

**Deploy notes:** one new route; no migration. Full suite green (21 runs, 0 failures).

### Step 5 — Update /api-docs for easy integration ✅

**What changed** — `app/views/pages/api_docs.html.erb`

- "Getting Started" now says: create an account → get your key from the dashboard → send it in `X-API-Key`. Credential shown as `ak_your_key_from_the_dashboard`.
- Removed the old shared-password guidance and the "append your affiliate code (`YOUR_API_KEY_AFF-000001`)" instructions. Docs now state attribution is automatic from the key — no affiliate code to pass.
- Added a **Quick start** block with copy-paste snippets: **cURL**, **JavaScript (web) `fetch`**, and **Swift (iOS) `URLSession`** — directly serving "integrate into their iOS or web app very easily."
- Corrected the docs to match the real API:
  - Both endpoint header examples use `ak_your_key`.
  - Mockups request body trimmed to the fields the endpoint actually reads (`product_id`, `variant_id`, `image_url`, optional `third_party_*`); removed the unused `shipping_address`; added a field-notes line.
  - Mockups response corrected to the real shape (wrapped in `data`, **201 Created** not 200).
  - Order response example uses a realistic `ORD-YYYY-XXXX` order number.
- Base URL updated to `https://appcessorise.com/api/v1`.

**Tests added:** `test/integration/api_docs_page_test.rb` — page renders, shows `X-API-Key`/`ak_your_key` and the Swift + JS snippets, and no longer contains the old `YOUR_API_KEY_AFF-` guidance.

**Deploy notes:** view-only. Full suite green (22 runs, 0 failures).

### Security — payment verification on the order API (branch `fix-payment-verification`)

**The hole (critical, pre-existing):** `POST /api/v1/orders` accepted `payment_intent_id` as an unchecked client string, marked the order `paid`, and submitted a real Printful order. With open affiliate signup, anyone could ship themselves free merchandise billed to us.

**The fix** — `app/controllers/api/v1/orders_controller.rb#verify_payment!` gates order creation on five checks against Stripe:
1. Intent exists on OUR Stripe account (`PaymentIntent.retrieve`; callers can't mint intents here — only `checkouts#mockup` does, server-side)
2. `status == "succeeded"`
3. `metadata.mockup_id` matches the order's mockup (kills cross-mockup replay — `checkouts#mockup` stamps this when creating the intent)
4. `amount_received` covers the quoted total (base + estimated shipping)
5. Intent not already consumed by another order

Failures return **402 Payment Required** (documented in `/api-docs`); Stripe outages return **503** rather than creating an unverified order.

**Replay protection at the DB:** partial unique index on `custom_orders.stripe_payment_intent_id` (`20260720000000` migration — raises with instructions if prod already has duplicates, which would itself indicate past replays) + model-level uniqueness validation.

**Legit flows unaffected:** the web mockup checkout (`mockup.html.erb` → same API) uses a genuine intent created for exactly the quoted total with matching metadata, so it passes all five checks.

**Tests:** `test/integration/api/v1/orders_payment_verification_test.rb` — 7 cases: fake intent 402, unpaid 402, wrong-mockup 402, underpaid 402, replayed 402, Stripe-down 503 (no order created), genuine payment → 201 + order + commission.

**Also noted (separate, not yet fixed):** `mockup.html.erb` embeds `ENV["INTERNAL_API_KEY"]` in client-visible HTML. With payment verification in place its blast radius is mockup generation (Printful quota), not free orders — still worth moving to a session-scoped internal endpoint.

### Security — dependency bumps (branch `security-gem-bumps`)

Ran on a separate branch after the affiliate work deployed. `bundle exec bundler-audit` had flagged **dozens** of advisories across framework and transitive gems; this clears them all (**bundler-audit: 0 remaining**).

**Notable version changes**

| Gem | From → To | Note |
|---|---|---|
| rails (+ actionpack/activesupport/activestorage/…) | 8.1.1 → 8.1.3 | XSS / DoS / path-traversal fixes |
| rack | 3.2.4 → 3.2.6 | multipart/host/static fixes |
| rack-session | 2.1.1 → 2.1.2 | session forgery fix |
| **puma** | **7.1.0 → 8.0.2** | **major bump** (app server) — PROXY-protocol DoS fixes |
| **devise** | **4.9.4 → 5.0.4** | **major bump** (auth) — open-redirect + confirmable fixes |
| nokogiri | 1.18.10 → 1.19.4 | many memory-safety fixes |
| jwt | 3.1.2 → 3.2.0 | empty-key HMAC bypass |
| net-imap | 0.5.12 → 0.6.4.1 | command-injection fixes |
| faraday, httparty, oauth2, loofah, rails-html-sanitizer, json, bcrypt, concurrent-ruby, addressable, msgpack, crass, action_text-trix, websocket-driver | various | patch/minor security fixes |
| minitest | 5.26.1 → **5.27.0 (pinned `~> 5.25`)** | pinned back off the transitive 6.0 major, which dropped the `minitest/mock` path our tests use |

**Verification of the two major bumps**
- **Devise 5:** new `test/integration/registration_flow_test.rb` exercises the *real* Devise flow (not the `sign_in` helper) — sign-up/sign-in pages render, a real signup creates an affiliate + API key and authenticates, login works, wrong password is rejected.
- **Puma 8:** booted the actual server — Puma 8.0.2 starts and serves `/`, `/up`, `/api-docs`, `/users/sign_in` (200) and the API (401 without key).

**Status:** all checks green — full suite **26 runs, 0 failures**, Brakeman clean, bundler-audit clean, RuboCop clean. **Merged to `main` 2026-07-20** after the payment-verification fix; no migrations.

### Security — remove leaked INTERNAL_API_KEY from checkout page (2026-07-20)

**The hole:** `mockup.html.erb` embedded `ENV["INTERNAL_API_KEY"]` in client-visible HTML so the page's JS could call `/api/v1/orders`. Anyone could view-source the key and use it against the API (post-payment-fix blast radius: burning Printful mockup quota).

**The fix:**
- `app/services/order_creation_service.rb` (new) — order creation, payment verification, Printful submission and commission logic extracted from the API controller into one service.
- `CheckoutsController#complete` (new, `POST /checkout/complete`) — first-party endpoint for the checkout page, protected by Rails CSRF instead of an API key. Same `OrderCreationService` gate — payment verification applies identically.
- `mockup.html.erb` — JS now posts to `/checkout/complete` with `X-CSRF-Token`; the embedded key is gone.
- `Api::V1::BaseController` — the `INTERNAL_API_KEY` auth path is **removed entirely** (its only consumer was this page, and the leaked value must not stay valid). Legacy `API_PASSWORD` fallback unchanged.
- `rack_attack.rb` — `/checkout/complete` throttled like API order creation (10/min/IP).

**⚠️ Operator action:** delete the `INTERNAL_API_KEY` env var from Coolify — the app no longer reads it, and the value should be treated as compromised.

**Tests:** `test/integration/checkout_complete_test.rb` — keyless completion creates order + attribution; payment verification still gates the web path (fake intent → 402); checkout page HTML contains no `X-API-Key` and references the CSRF flow. Full suite 36 runs, 0 failures.

### Reliability & conversion batch (branch `reliability-and-conversion`, 2026-07-21)

**1. Solid Queue actually works now (critical, pre-existing).** `production.rb` set `queue_adapter = :solid_queue` but the Solid Queue tables were never created anywhere (no queue database configured, none in the primary schema) — so **every `deliver_later`/`perform_later` in production raised**. Fixed with `20260720000001_create_solid_queue_tables` (tables into the primary DB, same pattern as the earlier solid_cache fix) and `SOLID_QUEUE_IN_PUMA=true` defaulted in the Dockerfile so the worker supervisor runs inside Puma. Order-status emails will now actually send.

**2. Mockups persisted to the DB.** New `mockups` table + `Mockup` model (`20260720000002`). Previously mockups lived only in Rails.cache with a 24h TTL — an eviction between the customer paying and the order call left a paid customer with "Mockup not found". Now: DB-backed with `expires_at` (24h) and `consumed_at` (one order per mockup), legacy cache fallback for in-flight mockups created before deploy, and `custom_orders.mockup_id` linking sales to mockups for funnel analytics (mockups created vs. converted).

**3. Printful submission is retry-safe.** New `SubmitPrintfulOrderJob`: the service still tries inline first (API response keeps `printful_order_id` when Printful is up), but any failure now queues the job, which retries 5× with backoff and marks the order `printful_status: "submission_failed"` if it ultimately can't — a paid order is never again silently left unfulfilled. Commission creation moved into the job (idempotent, created on successful submission).

**4. Conversion copy.** `commission_percent` helper (single source of truth from `DEFAULT_COMMISSION_RATE`). Homepage hero: "you earn **15% of every sale**" + key-facts strip (15% / free, 2 API calls / we print & ship) + new dark "Integrated in an afternoon" section with the fetch snippet and docs/signup CTAs. Signup page: headline is now "**Start earning 15% on every sale**" with the instant-API-key promise, and the old boxed-A logo replaced with the lowercase wordmark.

**5. Products page is real.** `ProductsController#index` renders the synced Printful catalog (`PrintfulProduct.active`, price-sorted): price, **"You earn ~$X per sale"**, variant count, and the API `product_id` per card, with an honest "catalog is being stocked" empty state (the old page was hardcoded fake products with fake reviews). Fixture fix: `variant_data` was stored as a JSON *string*, silently defeating the `active` scope in tests.

**Deploy notes:** two migrations (solid_queue tables, mockups) — auto-run on deploy. Tests: 49 runs, 0 failures; Brakeman/RuboCop/Zeitwerk clean.

---

## Summary & follow-ups

The full affiliate loop is now in place: **sign up (→ affiliate + API key) → integrate with one header (cURL/JS/Swift) → sales auto-attributed → dashboard shows real commissions.** A pre-existing production 500 in the order API (commission column/association collision) was fixed along the way.

**Not done / suggested next:**
- Retire the legacy shared `API_PASSWORD` fallback (and the `_AFF-` param path) once all affiliates are on `ak_` keys.
- Products page (`ProductsController#index` still empty) — decide Printful catalog vs. landing.
- P3 items from `todo.md` (email confirmation, Resend password-reset verification, Printful sync E2E, Solid Queue worker).
- Consider hashing API keys at rest (currently stored plaintext, like many API-key systems; fine to ship, worth revisiting).
