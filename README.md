# Prospect

Prospect is an iPhone app for teams that collect prospects at events: open days, fairs, forums. Each person records visitors on their own phone. **Nothing is sent to a server**: the data stays on the phones of the team, and the organizer collects it at the end of the event.

```
ios/   iPhone app: SwiftUI, iOS 18+, Live Activity extension
```

The previous hosted version (accounts, a Hono API on Vercel, Postgres on Neon) lives on the `hosted` branch.

## How it works

1. **Organizer** opens the app, chooses *Organiser un événement*, gives their name and creates an event (name, date, optional end time, programs).
2. The **Collecte** tab shows an **invitation**: a QR code and a share link. Agents scan it with Prospect (*Rejoindre un événement*), enter their name, and the event appears on their phone. No account.
3. During the event everybody records prospects on their own phone, and sees only their own list.
4. At the end, each agent opens the **Envoi** tab and taps *Envoyer*: the app builds a **file encrypted for the organizer** and opens the share sheet (AirDrop, Messages, Mail…). Phones remind agents at the event's end time.
5. The organizer opens the file in Prospect (or taps *Importer un envoi*). Prospects are merged without duplicates, possible duplicates (same email or phone) are flagged, and the dashboard and CSV export cover the whole event.

### Privacy

- The event's **private key never leaves the organizer's phone** (Keychain). Agents hold only the public key, from the invitation.
- A handover file is encrypted with an ephemeral key per file (Curve25519 key agreement, HKDF-SHA256, AES-256-GCM). It can travel through any channel; only the organizer's phone can open it, and a tampered file is rejected.
- The local store is a JSON file with complete file protection (readable only while the phone is unlocked). There is no analytics, no account, no network code.
- "Réinitialiser cet appareil" (Profil) wipes everything, including keys.

### Limits to know

- Agents see only their own prospects until the organizer has imported their file: there is no live view.
- A lost or broken phone loses what it recorded and had not yet sent. A mid-day send limits that.
- The organizer's key is stored only on their phone (this device only, not synced). If that phone is lost, received handovers can no longer be opened.
- iOS only.

## The iPhone app (`ios/`)

The Xcode project is generated from `ios/project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen). Source folders are synced, so files added in Xcode are picked up without regenerating.

- **Run:** `cd ios && xcodegen && open Prospect.xcodeproj`.
- **Unit tests:** `xcodebuild test -project ios/Prospect.xcodeproj -scheme Prospect -destination 'platform=iOS Simulator,name=iPhone 18 Pro Max' -only-testing:ProspectTests`.
- **Debug builds** have a floating bug button with demo states (first launch, organizer, agent) and a *Simuler l'envoi d'un agent* action, so the whole handover can be tried on one phone. Launch arguments: `-debugScenario <fresh|freshOrganize|freshJoin|organizerEmpty|organizerFull|agentFull>`, `-debugRoute <newProspect|editProspect|filters|events|newEvent|invitation|profile>`.

Structure: `Local/` (store, key vault, invitation, encrypted handover, merge) → `Services/` (`ProspectService` answers from the store) → `ViewModels/` (`@Observable`) → `Views/`. Colors live in `Color+Tokens.swift`; the design system in `Views/DesignSystem/`. The app is dark-mode only.
