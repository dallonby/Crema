# CaffeCrema Labs — Privacy Policy

**Effective:** 27 May 2026
**Last updated:** 27 May 2026

CaffeCrema Labs (the "App") connects your iPhone, iPad, or Mac to a Wendougee LITA espresso machine over Bluetooth Low Energy, lets you design and run brew profiles, and offers an optional community feature for sharing recipes. This document explains what data we collect, why, and how we handle it.

## What runs on your device only

The following stay on your device. They are **not** transmitted to our servers:

- Your brew profile library
- Shot history with tasting notes and yield
- Paired machine identifiers and connection state
- Any profile you author but don't explicitly share

## What we collect when you sign in

Sign In is optional and only required for the community sharing features. When you sign in with Apple or Google:

- We receive a pseudonymous **user identifier** (`sub`) from the provider — a stable opaque string that identifies you across sessions. We never receive your Apple ID, your Google email, or your real name from this. Google additionally provides display name + avatar URL if you grant the `profile` scope.
- We store this identifier alongside a **display name** you choose (defaults to a name fragment if not provided).
- We do **not** receive or store your email address from the sign-in provider.

## What we collect when you share a profile

When you tap **Share** on a profile and choose **Upload to community**:

- The full **brew profile** (recipe shape — pressure / flow / time values, equipment notes you optionally attach, bean name if you provide one) is uploaded to our server.
- The shared profile is **public** — anyone with the link or browsing the community feed can view and import it.
- Your display name is associated with the upload.

## Likes and follows

- Profiles you like are recorded server-side so the count on each profile is accurate.
- Users you follow are recorded server-side so we can show "people you follow" feeds in future versions.
- Both are **public** signals.

## What we do NOT collect

- Location data
- Health or fitness data
- Contacts
- Photos or files outside what you explicitly attach to a shared profile
- Browsing history or search history
- Financial information
- Advertising identifiers (IDFA / GAID)
- Crash analytics (we use no third-party analytics or crash reporters)

## Tracking

We do not track you across apps or websites. We do not share data with advertising networks. No third-party analytics SDK runs in the app.

## Bluetooth

The app uses Bluetooth LE to communicate with your espresso machine. This data:

- Stays on your device
- Is not transmitted to our servers
- Includes brew telemetry (pressure, flow, volume readings during a shot) and brew control commands

The system Bluetooth permission prompt explains this in the same words you read here.

## Children

The app is not directed at children under 13 and is rated 4+ for App Store classification. We do not knowingly collect data from children.

## Your rights

You can:

- **Delete an uploaded profile** at any time from within the app — it is removed from the server immediately.
- **Sign out** from Settings → Sign Out. This clears local session data but does not delete server-side records.
- **Delete your account** by emailing da@byeq.com with the display name on your account. We will purge your user record + all uploaded profiles within 14 days. (An in-app account-deletion button is on the v0.3 roadmap.)

## Data location

Our backend currently runs in the United Kingdom and stores data in PostgreSQL. We do not transfer data outside the UK.

## Changes

If we change this policy in a material way, we will note the date of change at the top of this page and surface a notice in the app on next launch.

## Contact

da@byeq.com
