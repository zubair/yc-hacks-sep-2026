# Postcard backend: team setup

How the four of us use the Supabase backend. The technical details (architecture, RPCs, errors) are in [backend/README.md](README.md).

**Summary:** everyone develops against their own local Supabase. One hosted project is the shared demo backend. Only the backend owner deploys to it.

## Who needs what

| Person | Works on | Supabase dashboard access | Needs |
|---|---|---|---|
| **Zafar** | Backend (`supabase/`, `backend/`) | Owner | Database password and secret key. Deploys migrations. |
| **Pranav** | Swift service adapter | Read-only (optional, for looking at tables and logs) | Local stack, `backend/fixtures/`, hosted URL + publishable key |
| **Zubair** | iOS app and Duo integration | Developer, only if he runs final integration and deploys | Hosted URL + publishable key in the app's git-ignored config |
| **Barrat** | UI and design | None | Nothing. Views use fixtures and previews. |

**Never share** the database password or the **secret key**, and never commit them or put them in the iOS app. The **publishable key** is meant to ship in apps and is fine to post in team chat.

## 1. Local backend (everyone who touches data)

Requires Docker Desktop (running) and Node.js.

```sh
npm i -g supabase
git fetch origin && git checkout team/zafar     # or integration/final once merged
supabase start          # first run downloads images (a few minutes)
supabase db reset       # applies migrations + creates demo users
supabase status -o env  # shows API_URL and PUBLISHABLE_KEY for your machine
```

Demo users (local only, password `postcard-local-1`):

| Email | Username | Use as |
|---|---|---|
| alice@postcard.test | alice | sender |
| bob@postcard.test | bob | recipient |
| eve@postcard.test | eve | outsider |

Local app config uses `SUPABASE_URL=http://127.0.0.1:54321` and `SUPABASE_PUBLISHABLE_KEY` from `supabase status`. An iOS simulator on the same Mac reaches `127.0.0.1`. A physical phone needs your Mac's LAN IP instead.

Useful commands:
- `supabase stop` stops the local stack.
- `supabase db reset` wipes local data and re-seeds.
- Studio (a table browser) runs at http://127.0.0.1:54323 after `supabase start`.

If image downloads fail from `public.ecr.aws`, run `export SUPABASE_INTERNAL_IMAGE_REGISTRY=docker.io` before `supabase start`.

### Run the backend tests

```sh
cd tests/backend && npm install
SUPABASE_PUBLISHABLE_KEY=<from supabase status> SUPABASE_SECRET_KEY=<from supabase status> npm test   # expect 27 passing
```

## 2. Hosted demo backend (owner does this once)

1. In the Supabase dashboard, create a project, for example `postcard`, in the team org. Save the database password in a password manager, not in chat or git.
2. From the repo root on `team/zafar`:
   ```sh
   supabase login
   supabase link --project-ref <project-ref>   # ref is in the dashboard URL: /project/<ref>
   supabase db push                            # applies supabase/migrations only
   ```
   Do **not** run `supabase/seed.sql` against the hosted project. It creates local demo accounts.
3. Check in the dashboard:
   - Storage → `postcard-photos` is **Private**, 10 MB, `image/jpeg`.
   - Database → Publications → `supabase_realtime` includes `postcards`.
   - Authentication → Sign In / Providers → decide whether to require **email confirmation**. For a hackathon demo, turning it off lets people sign in right after signing up.
4. Project Settings → API Keys: post **Project URL** and **Publishable key** to the team.
5. Organization Settings → Team: invite teammates using the roles in the table above.

Future backend changes always go in a **new** migration file. Never edit one that has already been pushed. Deploy with `supabase db push`.

## 3. Using the hosted demo

- Put the hosted `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` in the app's local config file. It is git-ignored; see `ios/README.md` once Zubair adds it.
- Each person signs up in the app with a real email and a username (3–30 characters: lowercase letters, numbers, `_`).
- Send a postcard by typing the other person's exact username. There is no contact list or public directory.
- "Sent" means the backend stored it. There are no delivery or read receipts in v1.

## 4. Rules of the road

- Stay in your owned paths (`docs/OWNERSHIP.md`). Backend changes go through Zafar.
- Never test against the hosted project with fake mass data. Use your local stack.
- Photos: the app uploads a JPEG under 10 MB to `<your user id>/<draft id>/photo.jpg` (both UUIDs **lowercase**; Swift's `uuidString` is uppercase) before calling `send_postcard`. Signed photo links must request 5 minutes or less.
- Problems: check `handoffs/zafar.md` for known limitations before filing a bug.
