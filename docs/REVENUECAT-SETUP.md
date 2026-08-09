# Purchases setup: App Store Connect → RevenueCat

Ream sells three non-consumables that all grant the same entitlement. Nothing functional is
behind them — they unlock accent finishes only.

## Values that must match exactly

| Thing | Value | Where it lives in code |
|---|---|---|
| Bundle ID | `com.lavailabs.ream` | `project.yml` |
| Team ID | `84FW6HJMUP` | `project.yml` |
| Entitlement | `Supporter` | `SupporterService.entitlementID` |
| Product 1 | `com.lavailabs.ream.supporter` — $2.99 | `SupporterService.Tier` |
| Product 2 | `com.lavailabs.ream.supporter.plus` — $4.99 | `SupporterService.Tier` |
| Product 3 | `com.lavailabs.ream.supporter.max` — $9.99 | `SupporterService.Tier` |
| API key | `appl_…` | `SupporterService.apiKey` ⚠️ placeholder today |

**Case matters on the entitlement.** If `Supporter` here and in the dashboard ever disagree,
every supporter silently becomes a non-supporter — no error, no log, just locked finishes.

Package identifiers do **not** matter. The code takes `offerings.current.availablePackages`,
sorts by price, and reads everything from `storeProduct`. Name them whatever the dashboard
suggests.

---

## Part 0 — prerequisites

1. **Sign the Paid Applications Agreement.** App Store Connect → Business → Agreements.
   Until it is *Active*, products never load and offerings are empty. This is the single most
   common cause of "RevenueCat returns nothing" and it looks identical to a config error.
2. **Register the bundle ID** (`com.lavailabs.ream`) and create the app record in ASC.

## Part 1 — App Store Connect

For each of the three products: **Monetization → In-App Purchases → +**

3. Type: **Non-Consumable**. Not consumable — a consumable that grants permanent
   functionality is a 3.1.1 rejection, and it cannot be restored.
4. Reference name (internal) and Product ID from the table above.
5. Price: $2.99 / $4.99 / $9.99.
6. **Localization** (English) — these match what shipped in the app's copy:

   | Product | Display Name | Description |
   |---|---|---|
   | `.supporter` | Supporter | Unlocks all five finishes |
   | `.supporter.plus` | Generous Supporter | Same finishes, more generous |
   | `.supporter.max` | Very Generous Supporter | Same finishes, remarkably generous |

7. **Review screenshot** — required once per product before first submission. A capture of
   Settings → Finish showing the tiers is enough.
8. **Review notes**: state plainly that these unlock cosmetic accent colours only and that no
   functionality is gated. Reviewers check this against the paywall copy.
9. Each product should reach **Ready to Submit**, and all three must be attached to the first
   app version you submit.

## Part 2 — RevenueCat

10. Create a project, then an **App** inside it: platform iOS, bundle `com.lavailabs.ream`.
11. **App Store Connect API key** — RevenueCat needs it to verify purchases and receive
    server notifications. ASC → Users and Access → Integrations → App Store Connect API,
    generate a key with *App Manager* access, upload the `.p8` to RevenueCat.
12. **Products** → import from App Store Connect, or add the three IDs by hand.
13. **Entitlements** → new entitlement, identifier exactly `Supporter`. Attach **all three**
    products to it. All three granting one entitlement is the design: the tiers exist to
    anchor price, not to unlock different things.
14. **Offerings** → create one (`default` is fine), add a package per product, and mark the
    offering **Current**. `offerings.current` is what the app reads; an offering that isn't
    Current resolves to nothing.
15. **Project settings → API keys** → copy the **public** app-specific key starting `appl_`
    into `SupporterService.apiKey`. It is designed to ship in the binary and grants no write
    access.

## Part 3 — testing

16. Sandbox tester: ASC → Users and Access → Sandbox → Testers. Sign into it on the device
    under Settings → App Store → Sandbox Account.
17. Run from Xcode on a **real device**. Non-consumables can be re-bought in sandbox by
    clearing purchase history for that tester.
18. Verify: three tiers appear with **localised prices from the store**, buying one flips
    every finish unlocked, and Restore Purchase re-grants after a delete/reinstall.

Turn **Settings → Debug → Supporter Mode** off first, or entitlement is forced on and the
purchase path is never exercised.

## Gotchas, in the order they usually bite

- **Empty offerings** is almost always one of: Paid Apps agreement not Active, offering not
  marked Current, or product IDs not matching character for character.
- **`Ream.storekit`** was for the direct StoreKit implementation this replaced. RevenueCat
  talks to the real store, so treat the device + sandbox as the source of truth rather than
  the local config.
- **`simctl launch` does not apply a scheme's StoreKit configuration**, so the Simulator can
  never show real prices. That is what the DEBUG Supporter Mode override exists for.
- Prices come from `storeProduct.localizedPriceString`, never a hardcoded string — otherwise
  every customer outside the US is quoted dollars for a purchase in their own currency.
