# Prospect

Prospect is an iPhone app for teams that collect prospects at events: open days, fairs, forums. Several people register visitors live on their own phones. Admins follow the numbers on a shared dashboard and export them as CSV.

```
api/   Backend: TypeScript + Hono, deployed on Vercel, Postgres on Neon
ios/   iPhone app: SwiftUI, iOS 18+, Live Activity extension
```

## How access works

| Who | Signs in with | Can |
|---|---|---|
| **Admin** | Email + password (no verification email) | Create organizations, programs and events; see every event; manage codes and people |
| **Agent** | The event's **agent code** + their name | Add, edit and archive prospects of **that event only** |
| **Conseiller** | The event's **conseiller code** + their name | Read prospects and the dashboard of **that event only** |

1. An admin creates an account and an **organization**. They choose what their events are called ("JPO", "Salon"…) and list the **programs** prospects can be interested in.
2. They create an **event**. It comes with two 6-character codes, under Prospects → ⋯ → *Codes d'accès*.
3. They share a code. People open the app, choose **Rejoindre**, and type the code and their name. No account, no email.
4. Admins can regenerate a code (people who already joined stay in) and remove people (they lose access right away). Codes stop working once the event is archived.
5. Co-admins join an organization with its **admin code** (Équipe tab).

The app checks for new prospects every 5 seconds while a list is open. There is no realtime push.

## Backend (`api/`)

- `src/index.ts`: the Hono app. Vercel deploys it as-is, with no config file.
- `src/routes/`: `auth` (signup, login, join, refresh), `me`, `orgs` (organizations, admins, programs), `events` (events, codes, participants, prospects, stats).
- `db/migrations/*.sql`: the schema. `npm run migrate` applies the files that haven't run yet.
- Security: every query is scoped to the caller's organization, and participants also to their event. Passwords are hashed with scrypt. Access tokens last 1 hour. Refresh tokens rotate on every use, and reusing an old one revokes every session of that account. Failed logins and code guesses are rate-limited.

### Run it locally (no database to install)

```bash
cd api
npm install
npm run dev:local     # http://localhost:3000, embedded Postgres stored in api/.pglite
```

```bash
npm test              # 17 end-to-end API tests against a real Postgres engine (PGlite)
npm run typecheck
```

### Deploy to Vercel + Neon

1. **Vercel → Add New → Project**, import this GitHub repo, and set **Root Directory** to `api`. Vercel detects Hono by itself.
2. In the project, **Storage → Create Database → Neon (Postgres)** and connect it. This sets `DATABASE_URL`.
3. **Settings → Environment Variables**: add `JWT_SECRET` (generate it with `openssl rand -base64 48`).
4. Create the tables once, from your machine, using the Neon connection string:
   ```bash
   cd api && DATABASE_URL="postgres://…" npm run migrate
   ```
5. Redeploy. `https://<your-project>.vercel.app/` answers `{"name":"prospect-api","ok":true}`.

Every push to `main` redeploys the API. When you add a migration, run `npm run migrate` against Neon again.

## iPhone app (`ios/`)

The Xcode project is generated from `ios/project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen). Source folders are synced, so files added in Xcode are picked up without regenerating.

- **API address:** set `API_BASE_URL` in `ios/project.yml`, then run `cd ios && xcodegen`. To use the local API instead, build with `API_BASE_URL=http://localhost:3000`.
- **Unit tests:** `xcodebuild test -project ios/Prospect.xcodeproj -scheme Prospect -destination 'platform=iOS Simulator,name=iPhone 18 Pro Max'`.
- **End-to-end UI test** (opt-in, against the local API only): see the header of `ios/ProspectUITests/ProspectFlowUITests.swift`.

Structure: `Services/` (API client, auth, data service) → `ViewModels/` (`@Observable`, injectable service) → `Views/`. Colors live in `Color+Tokens.swift` and fonts (Geist) in `Font+Geist.swift`. The app is dark-mode only.
