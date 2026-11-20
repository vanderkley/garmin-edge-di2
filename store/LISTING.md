# Di2 Gear and Battery: Connect IQ Store listing

Garmin developer site → **Upload an App** (or **Update** for a new version). The texts per
language (Title, Description, What's New) are in [DESCRIPTIONS.md](DESCRIPTIONS.md): copy and
paste them as they are. This file covers the rest of the form.

## The form, field by field

| Field | Value / file |
|---|---|
| App file | `../bin/Di2.iq` (`scripts/build.sh export`). "Signature check failed" on a first upload with SDK 9.x is a known store bug: continue |
| Version | `1.0.1` |
| Title, Description, What's New | [DESCRIPTIONS.md](DESCRIPTIONS.md); English first, then the other 25 languages via "Select a Language → Add" |
| Hero Image (1440×720) | `02-hero.gif` (animated) or `02-hero.png` |
| Category / Subcategory | Data Fields / Cycling |
| Does your app collect user data? | **No**: the license e-mail and code stay on the Edge, the app never goes online |
| ANT+ profiles | **No** (the field uses Bluetooth) |
| Regional limits | **No** |
| Cover Image (500×500) | `01-icon.png` |
| Icons for App Store on Device | No |
| Screen Images | `03-edge-less.gif`, `04-edge-1050.gif`, `05-edge-explore-2.gif`, `06-edge-explore-3.gif`, `07-edge-1040.gif`, `08-edge-840.gif`, `09-garmin-connect.png` |
| Preview video | (empty) |
| Activity Types | **Cycling** |
| Email Address (public) | `info@buienrit.nl` |
| Source Code URL | https://github.com/vanderkley/garmin-edge-di2 |
| Review notification | Yes |
| App Migration | Yes |
| Monetization | **Yes** → How: **Other** → **Third-Party Payments** only (not Merchant Account, not Tips, not Subscription) |
| Companion App | (empty) |

## Payment

The app needs a license after the **50 km free trial**: one-time **€8**, ordered on
https://buienrit.nl/di2. The customer gets a payment request by mail; once it is paid the
license code is mailed (buienrit-server, admin page → Paid). The code is checked on the Edge
itself, from the e-mail address and the secret in `source/Di2Secret.mc`.

Garmin rejected the first upload (2026-11-09) because the payment type was missing: always
mark the app as requiring payment **and** pick Third-Party Payments.

## Support

- E-mail: info@buienrit.nl
- Website: https://buienrit.nl/di2
- Source and issues: https://github.com/vanderkley/garmin-edge-di2
