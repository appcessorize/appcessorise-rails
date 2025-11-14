# Printful API Integration Plan

## Overview
Build an API-first print-on-demand service where 3rd party apps can submit images, generate product mockups via Printful, and complete purchases with Apple Pay. Track affiliates and orders in admin/affiliate dashboards.

## Architecture Flow

```
3rd Party App/Website
    ↓ (POST image + affiliate_code)
Our API Endpoint
    ↓
Printful API (Generate Mockup)
    ↓
Return Mockup to 3rd Party
    ↓ (User clicks Buy)
3rd Party Redirects to Our Checkout
    ↓
Our Checkout Page (mockup + original image + price)
    ↓ (Apple Pay / Stripe)
Payment Processed
    ↓
Create Printful Order
    ↓
Store Order Data in DB
    ↓
Update Admin & Affiliate Dashboards
```

## Printful API Information

### Authentication
- **Method**: OAuth Private Token (recommended for this use case)
- **Rate Limit**: 120 API calls per minute
- **API Version**: Use v2 (beta) for better features

### Key Endpoints Needed

1. **Catalog API** - Get available products
   - `GET /products` - List all products
   - `GET /products/{id}` - Get product details
   - `GET /products/{id}/variants` - Get product variants (sizes, colors)

2. **Mockup Generator API**
   - `POST /mockup-generator/create-task/{id}` - Create mockup generation task
   - `GET /mockup-generator/task` - Get mockup task result
   - Submit image + product variant → Receive mockup image URLs

3. **Orders API**
   - `POST /orders` - Create new order
   - `GET /orders/{id}` - Get order details
   - `GET /orders` - List all orders
   - Webhooks for order status updates

4. **Shipping API**
   - `POST /shipping/rates` - Calculate shipping costs

## Database Schema

### New Tables

#### `printful_products`
```ruby
- id (bigint)
- printful_product_id (integer) # Printful's product ID
- name (string)
- description (text)
- base_price (decimal)
- variant_data (jsonb) # Store variants (sizes, colors)
- mockup_template_ids (jsonb) # Printful template IDs for mockups
- created_at, updated_at
```

#### `custom_orders`
```ruby
- id (bigint)
- order_number (string, unique, indexed)
- affiliate_code (string, indexed)
- user_id (bigint, nullable) # If user is logged in
- email (string)
-
- # Product Info
- printful_product_id (integer)
- variant_id (integer)
- quantity (integer, default: 1)

- # Images
- original_image_url (string) # Customer's uploaded image
- mockup_image_url (string) # Printful generated mockup
-
- # Pricing
- product_price (decimal)
- shipping_cost (decimal)
- total_price (decimal)
- affiliate_commission (decimal)

- # Printful
- printful_order_id (integer, nullable)
- printful_status (string) # draft, pending, fulfilled, etc.
- printful_tracking_number (string)
- printful_tracking_url (string)

- # Shipping
- recipient_name (string)
- address_line1 (string)
- address_line2 (string)
- city (string)
- state (string)
- zip (string)
- country (string, default: "US")
- phone (string)

- # Payment
- stripe_payment_intent_id (string)
- payment_status (string) # pending, paid, failed, refunded
- paid_at (datetime)

- # Metadata
- third_party_app_name (string, nullable)
- third_party_order_id (string, nullable)
- notes (text)
-
- created_at, updated_at
```

#### `affiliate_commissions`
```ruby
- id (bigint)
- user_id (bigint) # Affiliate user
- custom_order_id (bigint)
- commission_amount (decimal)
- commission_rate (decimal) # e.g., 0.15 for 15%
- status (string) # pending, approved, paid
- paid_at (datetime, nullable)
- created_at, updated_at
```

## API Endpoints (Our API)

### 1. Generate Mockup (Public API)
**Endpoint**: `POST /api/v1/mockups`

**Headers**:
```
X-API-Key: {affiliate_api_key}
Content-Type: application/json
```

**Request Body**:
```json
{
  "affiliate_code": "ABC123",
  "product_id": 71, // Printful product ID (e.g., 71 = Unisex T-Shirt)
  "variant_id": 4012, // Size/color variant
  "image_url": "https://example.com/customer-design.png",
  "third_party_app_name": "MyCoolApp",
  "third_party_order_id": "order_xyz123"
}
```

**Response**:
```json
{
  "success": true,
  "data": {
    "mockup_id": "uuid-here",
    "mockup_image_url": "https://printful-mockups.s3.amazonaws.com/...",
    "original_image_url": "https://example.com/customer-design.png",
    "product_name": "Unisex Heavy Cotton Tee",
    "variant_name": "Black / L",
    "base_price": 29.99,
    "estimated_shipping": 5.99,
    "checkout_url": "https://appcessorise.com/checkout/uuid-here"
  }
}
```

### 2. Get Checkout Details
**Endpoint**: `GET /checkout/:mockup_id`

**Response**: HTML page with:
- Mockup image preview
- Original image preview
- Product details
- Price breakdown
- Shipping form
- Apple Pay / Stripe payment buttons

### 3. Create Order (After Payment)
**Endpoint**: `POST /api/v1/orders`

**Request Body**:
```json
{
  "mockup_id": "uuid-here",
  "payment_intent_id": "pi_stripe_id",
  "shipping_address": {
    "name": "John Doe",
    "address1": "123 Main St",
    "city": "New York",
    "state": "NY",
    "zip": "10001",
    "country": "US",
    "phone": "+1234567890"
  }
}
```

**Response**:
```json
{
  "success": true,
  "order_number": "ORD-2025-001",
  "printful_order_id": 12345678,
  "estimated_delivery": "2025-01-20",
  "tracking_url": null
}
```

### 4. Order Status Webhook (From Printful)
**Endpoint**: `POST /api/webhooks/printful`

Receives updates from Printful about order status changes.

## Implementation Steps

### Phase 1: Database & Models (Day 1)
- [ ] Create migrations for `printful_products`, `custom_orders`, `affiliate_commissions`
- [ ] Create models with validations and associations
- [ ] Seed Printful products (t-shirts, hoodies, mugs, etc.)

### Phase 2: Printful Integration (Day 2-3)
- [ ] Set up Printful API credentials in `.env`
- [ ] Create `PrintfulService` class
  - `sync_products` - Sync Printful catalog to our DB
  - `generate_mockup(image_url, product_id, variant_id)` - Create mockup
  - `calculate_shipping(address, items)` - Get shipping cost
  - `create_order(order_params)` - Submit order to Printful
  - `get_order_status(printful_order_id)` - Check order status

### Phase 3: Public API (Day 4-5)
- [ ] Create `Api::V1` namespace
- [ ] Implement API authentication (API keys for affiliates)
- [ ] Create `MockupsController#create` endpoint
- [ ] Store mockup data temporarily (Redis or DB)
- [ ] Return mockup URL and checkout link

### Phase 4: Checkout Flow (Day 6-7)
- [ ] Create checkout page with DaisyUI styling
- [ ] Display mockup image + original image
- [ ] Show product details and price breakdown
- [ ] Shipping address form
- [ ] Stripe Elements integration
- [ ] Apple Pay button integration (requires HTTPS)
- [ ] Handle payment confirmation
- [ ] Submit order to Printful after payment

### Phase 5: Admin Dashboard (Day 8)
- [ ] Orders list page (filterable by status, affiliate)
- [ ] Order detail page showing:
  - Customer info
  - Product mockup & original image
  - Printful order ID and status
  - Tracking information
  - Affiliate commission
- [ ] Bulk actions (cancel, refund)
- [ ] Export orders to CSV

### Phase 6: Affiliate Dashboard (Day 9)
- [ ] Generate unique affiliate codes
- [ ] Generate API keys for affiliates
- [ ] Show affiliate's orders
- [ ] Display commission earnings (pending/paid)
- [ ] API usage statistics

### Phase 7: Webhooks & Background Jobs (Day 10)
- [ ] Set up Printful webhooks endpoint
- [ ] Process order status updates
- [ ] Send email notifications (order confirmation, shipping updates)
- [ ] Background job to sync order statuses periodically

## Environment Variables

```env
# Printful
PRINTFUL_API_KEY=your_printful_private_token
PRINTFUL_WEBHOOK_SECRET=your_webhook_secret

# Stripe (existing)
STRIPE_PUBLISHABLE_KEY=pk_test_...
STRIPE_SECRET_KEY=sk_test_...

# Affiliate Settings
DEFAULT_COMMISSION_RATE=0.15 # 15%
```

## Security Considerations

1. **API Key Authentication**
   - Generate unique API keys for each affiliate
   - Rate limit API requests (120/min to match Printful)
   - Validate affiliate_code exists and is active

2. **Image Validation**
   - Validate image URLs are accessible
   - Check image file size (max 50MB)
   - Validate image format (PNG, JPG, SVG)
   - Scan for inappropriate content (optional: AWS Rekognition)

3. **Payment Security**
   - Use Stripe's SCA (Strong Customer Authentication)
   - Validate payment before submitting to Printful
   - Handle failed payments gracefully
   - Prevent duplicate orders

4. **Webhook Verification**
   - Verify Printful webhook signatures
   - Use HTTPS for all endpoints
   - Log all webhook events

## Commission Calculation

```ruby
# Example: 15% commission on product price (not shipping)
product_price = 29.99
commission_rate = 0.15
commission_amount = product_price * commission_rate # $4.50
```

## Cost Breakdown Example

```
Product Base Price: $29.99 (Printful cost to us: ~$15-20)
Shipping: $5.99
------------------
Subtotal: $35.98
Our Markup: 30% = $10.79
Affiliate Commission: 15% of $29.99 = $4.50
------------------
Customer Pays: $35.98
We Pay Printful: ~$20-25 (product + shipping)
Affiliate Earns: $4.50
Our Profit: ~$6-11
```

## Testing Strategy

1. **Printful Sandbox**
   - Use Printful's test API keys
   - Test mockup generation
   - Test order creation
   - Test webhook delivery

2. **Payment Testing**
   - Use Stripe test cards
   - Test Apple Pay in staging (requires HTTPS)

3. **API Testing**
   - Create test affiliate account
   - Generate test API key
   - Submit test mockup requests
   - Verify responses

## Monitoring & Analytics

1. **Track Metrics**
   - Mockup generation success rate
   - Conversion rate (mockups → orders)
   - Average order value
   - Affiliate performance
   - Printful API errors

2. **Logging**
   - Log all Printful API calls
   - Log payment attempts
   - Log webhook events
   - Alert on repeated failures

## Future Enhancements

- [ ] Multiple product support in single order
- [ ] Bulk mockup generation API
- [ ] Custom branding options
- [ ] Automatic fulfillment status emails
- [ ] Customer order tracking page
- [ ] Printful product catalog auto-sync
- [ ] Volume pricing for affiliates
- [ ] Recurring commission payouts (weekly/monthly)

## Notes

- Printful handles all printing, packaging, and shipping
- We never touch physical inventory
- Mockups are generated on-demand
- Orders are fulfilled by Printful automatically
- We focus on API, payments, and affiliate management
