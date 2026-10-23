# Tribe Time

A native iOS tribe organizer for planning, scheduling, meal planning, grocery lists, and chores — synced via iCloud.

**App Store / home screen name:** Tribe Time  
**Xcode target / bundle ID:** `FamilyHub` / `com.danielschwartzel.familyhub` (unchanged — renaming the bundle would break CloudKit and App Store Connect)

## Features

- **Calendar** — Shared tribe events with multi-day bars, member colors, and email import
- **Meal Planning** — Weekly meal plan, cookbook, favorite week plans, grocery list from meals
- **Household** — Budget, groceries, needs, and wish lists
- **Chores & Duties** — Recurring chores with local reminders
- **Tribe Members** — Color-coded profiles for assigning events and chores
- **iCloud Sync** — Private CloudKit sync across devices on the same Apple ID

## Requirements

- Xcode 16+
- iOS 17+
- Paid Apple Developer Program ($99/year) — required for iCloud / CloudKit
- Devices signed into iCloud (see sharing notes below)

## Getting Started

1. Open the project in Xcode:

   ```bash
   open ~/Projects/family-hub/FamilyHub.xcodeproj
   ```

2. Select the **FamilyHub** target → **Signing & Capabilities**
3. Check **"Automatically manage signing"**
4. Set **Team** to your **paid** Apple Developer team (not the free Personal Team)
5. Confirm these capabilities are present (they should already be in the project):
   - **iCloud** → CloudKit enabled  
     Container: `iCloud.com.danielschwartzel.familyhub`
   - **Push Notifications** (used for CloudKit sync)
   - **Background Modes** → Remote notifications
6. On each device: **Settings → [Your Name] → iCloud** — make sure iCloud is signed in
7. Pick a real iPhone (simulator CloudKit sync is unreliable) and press **⌘R**

### First launch after enabling sync

Delete the old local-only install of the app, then reinstall. Switching from a local store to CloudKit uses a new persistent store; old on-device data will not carry over automatically.

## Shared Tribe (Create / Invite / Join)

On the **Tribe** tab:

1. **Create shared tribe** — generates an invite code like `AB3K-9XP2`
2. **Share** the code or invite link with relatives
3. They open **Tribe Time** → **Join with invite code** (each person keeps their own Apple ID)

This uses **CloudKit Sharing**. Joining connects everyone’s Apple IDs to the same shared tribe.

**What syncs across the tribe:** everything — profiles, calendar events, chores, recipes, meal plans, favorite week plans, groceries, household needs, wish lists, budget items and expenses, income, recurring bills, voice memos, and email imports. Sync runs when you open the app, return to it, a few seconds after you make a change, or when you tap **Sync now** on the Tribe tab.

Edits and deletions are detected automatically at sync time (each device remembers a fingerprint of what it last synced), so new screens don't need to call any sync API. To add a new synced model, give it `modifiedAt` / `cloudSynced` fields, conform it to `FamilySyncable` in `Services/FamilySyncable.swift`, and add it to the `entities` list in `FamilySyncService`.

**Before shipping to TestFlight / App Store:** the new record types (`SharedMealPlan`, `SharedGroceryItem`, `SharedBudgetItem`, etc.) are created automatically in the CloudKit **Development** environment the first time they sync. Deploy the schema to **Production** in the CloudKit Console before releasing, or production builds won't be able to save them.

Test on **real devices** signed into iCloud (simulator sharing is unreliable). After upgrading, delete and reinstall if the store schema fails to migrate.

## CloudKit Dashboard (optional)

Inspect synced records at [CloudKit Console](https://icloud.developer.apple.com/):

1. Sign in with your developer Apple ID  
2. Select container `iCloud.com.danielschwartzel.familyhub`  
3. Use **Development** environment while testing from Xcode  

Schema is created automatically the first time the app syncs successfully.

## Project Structure

```
FamilyHub/
├── FamilyHubApp.swift          # App entry + SwiftData / CloudKit container
├── FamilyHub.entitlements      # iCloud CloudKit + push
├── Models/                     # CloudKit-compatible SwiftData models
├── Views/                      # Calendar, Meals, Household, Chores, Tribe
├── Services/
└── Extensions/
```

## Notes

- Bundle ID and CloudKit container stay as `familyhub` for continuity; only the **display name** and in-app wording use Tribe / Tribe Time.
- Prefer real devices over Simulator for CloudKit and push testing.
