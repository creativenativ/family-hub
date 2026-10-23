# Tribe Time: App Store submission

Everything below is ready to paste into App Store Connect. The screenshots are in `AppStore/screenshots/` at the required 6.9" iPhone size (1320×2868).

## Your checklist

Do these in order. Steps 1–3 come before you upload anything.

1. **Test on two real iPhones (strongly recommended).** Use two different Apple IDs, both signed in to iCloud. Create a home tribe on one phone and join with its code on the other. Check that events, chores, groceries and the whiteboard sync both ways. Also create a tribe calendar and use **Share to…** on an event. The simulator can't test any of this, and it's the part App Review is most likely to hit.
2. **Deploy the CloudKit schema to Production.** In Xcode, run the app on your phone once and touch each area (calendar, chores, meals, groceries, budget, wish list, tribes) so every record type gets created. Then go to [CloudKit Console](https://icloud.developer.apple.com/) → container `iCloud.com.danielschwartzel.familyhub` → **Deploy Schema Changes…** → Production. **If you skip this, sync won't work for anyone who downloads the app.** Repeat it after any update that adds new synced data.
3. **Turn on the privacy and support pages** (I can do this for you). You need these two links:
   - Privacy: `https://creativenativ.github.io/family-hub/privacy.html`
   - Support: `https://creativenativ.github.io/family-hub/`
4. **Create the app record.** Go to [App Store Connect](https://appstoreconnect.apple.com/) → Apps → **+** → New App:
   - Platform: iOS
   - Name: **Tribe Time** (if the name is taken, try "Tribe Time: Family Hub")
   - Primary language: English (U.S.)
   - Bundle ID: `com.danielschwartzel.familyhub`
   - SKU: `tribetime-ios`
5. **Archive and upload.** In Xcode, choose **Any iOS Device (arm64)** as the destination, then **Product → Archive**. When it finishes, the Organizer opens: choose **Distribute App → App Store Connect → Upload**. Keep the defaults, including automatic signing.
6. **Fill in the listing** using the text below. Upload the 4 screenshots, attach the build from step 5, and answer **App Privacy** and **Age Rating** as listed below.
7. **Submit for Review.** Optionally, send the build to yourself and family through **TestFlight** first.

## Listing text

**Name:** Tribe Time

**Subtitle** (29/30): Family calendar & chore board

**Promotional text** (142/170):
Bring the whole tribe together: shared family calendar, a chore whiteboard, meal plans, groceries and budget, synced privately through iCloud.

**Keywords** (95/100):
family,calendar,chores,planner,organizer,shared,household,meal,grocery,schedule,kids,whiteboard

**Category:** Productivity. **Secondary:** Lifestyle

**Description:**

Tribe Time keeps your household running in one place: everyone's schedule, who's doing which chore, what's for dinner and what you need from the store. It's all shared with the people you choose, through your own iCloud.

YOUR TRIBE, YOUR WAY
• Create a home tribe and invite family with a code or link. Everyone uses their own Apple ID.
• Join as many tribe calendars as you like: work, a sports team, a book club. Spin the bubble wheel to see them all.
• Share a single appointment from work to your family calendar without sharing anything else. It stays up to date if the time changes.

A CALENDAR THE WHOLE FAMILY CAN READ
• Color-coded events for each person and each tribe.
• Turn any tribe's calendar on or off with one tap.
• Multi-day events, reminders, and events imported from email.

THE CHORE WHITEBOARD
• Every common household chore, written in marker and grouped by room.
• Drag chores anywhere, add your own, and check them off with a satisfying marker tick.
• Member magnets show who's on what, and repeating chores reset themselves.

MEALS, GROCERIES AND HOME
• Plan the week's meals, save favorite weeks, and keep a family cookbook.
• Turn meal plans into a grocery list.
• Track the budget, bills, household needs and wish lists.

MAKE IT YOURS
• Pick a theme, from deep teal and brass to sage kitchen, or choose your own colors for every part of the app.
• Give any event or chore its own color.
• Choose from five app icons.

PRIVATE BY DESIGN
No ads, no tracking, no accounts to create. Your data lives on your devices and in your iCloud, and is shared only with the tribes you join.

**Support URL:** https://creativenativ.github.io/family-hub/
**Privacy Policy URL:** https://creativenativ.github.io/family-hub/privacy.html
**Copyright:** 2026 Daniel Schwartzel

## App Privacy (the "nutrition label")

Answer **"No, we do not collect data from this app."**

Data you store through CloudKit sits in the user's own iCloud account and isn't accessible to you as the developer, so Apple doesn't count it as collected. The app has no analytics, ads or tracking, and the privacy manifest (`PrivacyInfo.xcprivacy`) matches this answer.

## Age rating

Answer **None** to every content question, and **No** to unrestricted web access, gambling and contests. Shared tribes only include people the user invites, so it isn't public user-generated content. This gives a **4+** rating.

## Notes for App Review

Paste this into **App Review Information → Notes**:

> Tribe Time stores and shares data with Apple CloudKit, so it needs the device to be signed in to iCloud. No in-app account or login is needed. To try sharing: open the Tribe tab, tap "Set up home" in the center of the wheel, create a home tribe, and you'll get an invite code. A second device signed in with a different Apple ID can join with that code via + → Join. All core features (calendar, chore whiteboard, meals, groceries, budget, themes in the gear menu on the Tribe tab) also work on a single device without joining a tribe.

## Already handled in the project

- iPhone-only, portrait orientation.
- Export compliance: `ITSAppUsesNonExemptEncryption = NO`, so you won't be asked about encryption on every upload.
- Privacy manifest declaring UserDefaults use (reason CA92.1), no tracking and no data collection.
- Online recipe search is switched off. TheMealDB's free key only allows development use. To bring search back in an update, get a supporter key, put it in `RecipeSearchService.apiKey`, and set `isEnabled = true`.
- Debug-only demo data and launch flags are compiled out of App Store builds.
- Version **1.0**, build **1**. Raise the build number for every new upload, and the version for each public release.
