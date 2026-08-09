# App Store Listing — Ream

On-device document scanner that makes searchable PDFs. Free, no subscription.

Name / Subtitle / Keywords / Description all require a new app version to change.
Only Promotional Text is editable in App Store Connect at any time.

> **Scope guardrails (keep the copy honest).** Ream does **not**:
> - detect form fields automatically. That was built, tested against a real receipt, and
>   parked because it guessed wrong more often than right. No "auto-fill", "smart fields" or
>   "finds the blanks" language anywhere.
> - sync, back up to a cloud, or have accounts. Never imply a scan is safe if the phone is
>   lost. The export is the backup, and the listing should say so plainly.
> - recognise handwriting, or any language but English (`en-US` is the only recognition
>   language configured). No multi-language or handwriting claims.
> - run on iPad. iPhone only for v1.

---

## Metadata fields (copy-paste ready)

**App Name** (26/30)
```
Ream: Image to PDF Scanner
```

> Why not "Document Scanner": measured, that search is closed. CamScanner 1.86M ratings,
> Adobe Scan 1.58M, iScanner 1.39M, Genius Scan 1.35M. `image to pdf` is the one term with a
> real opening (opportunity 57, difficulty 41, and the #1 result had ~100 ratings). Spending
> title characters on a term four million-rating apps own would buy nothing.

**Subtitle** (28/30)
```
Scan to PDF, no subscription
```

> Doing two jobs: it carries the `scan`/`pdf` tokens AND states the differentiator in the one
> place a browsing user sees next to four apps that will charge them weekly.

**Keywords** (99/100, no spaces, no repeats of Name or Subtitle tokens)
```
document,doc,receipt,ocr,text,searchable,sign,signature,fill,form,paper,photo,jpg,converter,offline
```

> Apple indexes Name + Subtitle + Keywords together, so nothing here repeats `image`, `pdf`,
> `scan`, `scanner` or `subscription`. Never put a competitor's name in this field.

**Promotional Text** (editable any time, no review)
```
Free forever, with no subscription, no ads and no watermarks. Every scan becomes a searchable PDF, and nothing ever leaves your phone.
```

**Description**
```
Scan paper into clean PDFs you can actually search. Free, with no subscription, no ads, no watermarks and no account.

SEARCH INSIDE YOUR SCANS
Ream reads the words on every page as it scans. Search "dishwasher" and it finds the receipt, not just documents you remembered to name well. The text stays inside the PDF, so it is still searchable in Files, Mail, or anywhere else you send it.

NOTHING LEAVES YOUR PHONE
Scanning, text recognition and PDF creation all happen on your device. There is no account to make, no cloud, and no network access at all. Your documents are yours.

FILL IN AND SIGN
Type into a form, sign it with your finger, or draw on it freehand. Pick black, blue, red or white ink. A filled form stays searchable, because the text you add is real text and not a picture of words.

STAY ORGANISED
Give a scan a name, or let Ream take one from the page. File documents under as many labels as you like and filter by them. Every page gets a thumbnail so you can find a document by what it looks like.

MULTI-PAGE, ONE FILE
Scan as many pages as you need and get one PDF. Combining pages is the whole point of a scanner app, so it is not going behind a paywall.

BRING IN WHAT YOU ALREADY HAVE
Share a PDF or photo to Ream from Mail, Files, or anywhere else, and it becomes a searchable document like everything else.

YOURS TO KEEP
Export every scan as a plain ZIP of ordinary PDFs. No proprietary format, nothing locked in. A backup you can only open with the app that made it is not a backup.

FREE, AND HONEST ABOUT IT
Every feature above is free and always will be. If Ream saves you from a scanner subscription, there is a one-time Supporter tip inside that unlocks four extra accent colours. It unlocks nothing else. Nothing in this app is gated behind it.
```

**What's New** (v1.0)
```
First release.
```

---

## App Store Connect settings

| Field | Value |
|---|---|
| Primary category | Productivity |
| Secondary category | Business |
| Age rating | 4+ |
| Price | Free |
| In-App Purchases | Supporter $2.99 / Generous Supporter $4.99 / Very Generous Supporter $9.99 |
| Devices | iPhone only |
| Export compliance | `ITSAppUsesNonExemptEncryption` is already `false` in the plist, so the upload question is skipped |

**Privacy nutrition labels: Data Not Collected.** Ream has no analytics, no accounts and makes
no network requests of its own. RevenueCat is the only SDK, and it sees purchase transactions
only. Answer the questionnaire accordingly rather than guessing "maybe".

**App Review Notes** (App Store Connect → the version's *App Review Information → Notes*)
```
Ream is an offline document scanner. Scanning, text recognition and PDF creation all run on-device. There is no account, no server and no login, so no demo credentials are required.

IN-APP PURCHASES
The three purchases are optional, non-consumable tips. They unlock four alternative accent colours and nothing else. No scanning, OCR, PDF creation, editing, export or sharing feature is gated behind them, and the app is fully functional without any purchase. Restore Purchase is in the same screen.

TO REACH THEM
Open the app, tap the gear in the top right, then "Support Ream" or "Finish".

CAMERA
The camera permission is used only for scanning documents with the system document scanner. Nothing captured leaves the device.
```

**In-App Purchase Review Notes** (per product, in the IAP's own *Review Notes* field)
```
Optional tip. Unlocks four alternative accent colours in the app's Finish picker and nothing else. No functionality is gated behind this purchase; the app is fully usable without it. To reach it: open the app, tap the gear icon in the top right, then "Finish".
```

---

## Screenshots

Use the `app-store-screenshots` skill. Suggested order, strongest first:

1. **The library** with several labelled scans and thumbnails. Caption: "Every scan, searchable."
2. **Search mid-query**, showing a match found by a word inside a document. This is the whole
   pitch and it is invisible in a static shot of the library, so the caption has to carry it.
3. **Fill & Sign** with typed text and a signature on a form.
4. **The finish picker**, showing the app is customisable and that the tip unlocks colours.
5. **Onboarding card 3** (the struck-through list) as the closer: no subscription, no ads, no
   watermarks, no account.
