# ⛽ Fuel Station App (India)

A loyalty-card app for an Indian fuel station: a **native iOS app**, a **REST API backend**, and the **owner/staff tools**. It uses no paid services: no SMS OTP and no payment gateway.

```
backend/   Node.js + Express + PostgreSQL (Prisma) REST API
ios/       SwiftUI iOS 17+ app (customer + staff + admin in one app)
docker-compose.yml   one-command deploy on your own server
```

## How login works (no OTP costs)

1. The customer signs up with **name, mobile number, a 4-digit PIN** and, optionally, their vehicle. The account starts as **PENDING**.
2. The **super admin** verifies the account, either in the app (Admin → Verify customers, one at a time or in bulk) or through the API.
3. Once verified, the card activates. The customer gets the **welcome bonus**, and whoever referred them gets the **referral bonus**.
4. **Forgot PIN:** the customer visits the counter, and an admin resets the PIN after checking their identity.
5. Optional free **Google sign-in** (`/auth/google`) works after the customer links Google from their profile.

PIN logins are rate-limited (8 attempts per 15 minutes per phone and IP). Changing the PIN logs out all other devices.

## Roles

| Role | Can do |
|---|---|
| CUSTOMER | Card, points, rewards, offers, history, receipts, vehicles, reminders, bookings, feedback |
| STAFF | Everything above + **Pump** tab: scan the card QR → record a fill-up → points awarded automatically; scan reward codes |
| ADMIN | + **Admin** tab: analytics, fuel prices, customers, PIN reset, points adjustment, bookings, feedback replies, announcements |
| SUPERADMIN | + **verify / block accounts**, change roles, create staff, edit station & loyalty settings |

## Features

**Customer app**
- A loyalty card that changes colour by tier (Silver, Gold, Platinum), with a moving shine and a 3D flip to the QR code. A full-screen QR and barcode view turns the screen brightness up for scanning.
- Live fuel prices (Petrol, Diesel, Premium, CNG) with ▲▼ change since the last price.
- Tier progress bar and points multiplier (1×, 1.5×, 2×).
- Rewards catalogue, offers you can claim, and redemption codes shown as QR codes.
- Fill-up history and PDF receipts you can share.
- Insights: monthly spend chart, spend by fuel (donut chart) and **mileage in km/l** worked out from odometer readings.
- Vehicles (Indian number-plate format, including BH series).
- Reminders for PUC, insurance and servicing. These are also sent as **local iPhone notifications**, which is free.
- Bookings for car wash, oil change, PUC test and tyre check. Booking only, no payment.
- Station map, directions, call and WhatsApp buttons, and the list of services.
- Feedback with replies from the owner; a "Quality & quantity promise" page.
- Refer & earn, and an in-app notification inbox.

**Staff (Pump tab):** camera QR scanner with manual entry as a fallback, amount or quantity entry with quick buttons, odometer reading, a success screen with the points awarded and any tier upgrade, a summary of the current shift, and reward handover.

**Admin tab:** today's and 30-day sales chart, member counts, top customers, a pending-verification queue with bulk verify, price publishing, customer search (by name, mobile, card or vehicle) with points adjustment, PIN reset, block and role change, plus bookings, feedback and announcements.

## Run the backend locally

```bash
cd backend
cp .env.example .env            # edit DATABASE_URL / JWT_SECRET / SUPERADMIN_*
npm install
npx prisma migrate deploy
npm run db:seed                 # creates super admin + sample prices, rewards, offers
npm run dev                     # http://localhost:4000/api/v1
npm test                        # end-to-end API test (needs Postgres)
```

Set `SEED_DEMO=true` to also create a demo staff account (`9000000002` / `1111`) and a pending customer.

## Deploy on your server

```bash
cp backend/.env.example backend/.env    # set a strong JWT_SECRET and your SUPERADMIN_PHONE/PIN
DB_PASSWORD=choose-a-strong-one docker compose up -d --build
```

Put Nginx or Caddy in front of it for free HTTPS with Let's Encrypt, e.g. `https://api.yourstation.in`.

## Run the iOS app

You need a Mac with Xcode 15 or later.

```bash
brew install xcodegen
cd ios
xcodegen generate
open FuelStation.xcodeproj
```

- Set `API_BASE_URL` in `ios/project.yml` to your server, e.g. `https://api.yourstation.in/api/v1`. In Debug builds you can also change it in the app under Profile → Developer → Server address.
- To try it on a real iPhone during development, use your Mac's LAN IP, e.g. `http://192.168.1.5:4000/api/v1`.
- Running on your own iPhone from Xcode is **free**. Publishing on the App Store needs an Apple Developer account, which costs **$99 per year**.

## API overview (`/api/v1`)

| Area | Endpoints |
|---|---|
| Auth | `POST /auth/register`, `POST /auth/login`, `POST /auth/google`, `POST /auth/google/link`, `POST /auth/change-pin` |
| Public | `GET /public/station`, `/public/prices`, `/public/prices/history`, `/public/offers`, `/public/rewards`, `/public/announcements`, `/public/loyalty` |
| Me | `GET/PATCH /me`, `GET /me/dashboard`, `GET /me/insights`, `GET /me/transactions[/:id]`, `GET /me/transactions/:id/invoice.pdf`, `GET /me/points`, vehicles / reminders / bookings / feedback / notifications / referrals CRUD |
| Loyalty (verified only) | `POST /loyalty/rewards/:id/redeem`, `GET /loyalty/redemptions`, `POST /loyalty/offers/:id/claim`, `GET /loyalty/coupons` |
| Staff | `GET /staff/lookup?code=`, `POST /staff/transactions`, `POST /staff/redemptions/use`, `GET /staff/my-shift` |
| Admin | `GET /admin/analytics`, users list/detail, `POST /admin/users/:id/verify`, `POST /admin/users/verify-bulk`, block / reset-pin / role / points, `POST /admin/staff`, `POST /admin/prices`, rewards / offers / announcements CRUD, bookings, feedback reply, `POST /admin/broadcast`, settings |

Errors always look like `{ "error": { "message": "...", "code": "ACCOUNT_PENDING" } }`.
