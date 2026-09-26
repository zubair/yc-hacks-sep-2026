# Product brief

## Core idea

Postcard makes a personal photo and note feel like a postcard shared with someone you know. The visual direction is warm cream paper, dark green typography, a vermilion stamp, clear travel photography, and restrained motion. Barrat can refine this direction while keeping accessibility and legibility first.

## v1 flow

1. Sign in with email/password (Supabase Auth); use local demo fixtures when configuration is absent.
2. Select a known recipient by exact username. No contact scraping, address-book upload, or public user directory.
3. Choose a photo, write a note, and preview the photographic front and message back.
4. Opening the Duo reveals the back; closing an opened draft seals it. Buttons offer the same actions on ordinary iPhones and simulators.
5. Tap Send to explicitly publish a direct postcard message. Folding, animations, and demo playback never send.
6. The recipient sees the postcard in an inbox/conversation and opens it to read. Realtime refreshes a durable stored conversation; reconnecting refetches persisted messages.

## Required states

Front, writing, sealed, sending, sent, loading inbox, empty inbox, receiving a postcard, authentication required, offline/error with retry. Preserve the draft if sending fails or is canceled. 'Sent' means stored by the backend; do not claim delivered/read unless there is a confirmed receipt feature.

## Scope boundary

Account-to-account direct messaging is the first release. Printed postcards, payments, public anonymous links, push notification delivery, and read receipts are later work. A receiving screen inside the iOS app is required; a separate website is not required for this reset.

## Demo and quality

A fixture demo must run without credentials and show compose → open → seal → explicit send → recipient inbox. Clearly label demo data and simulated sends. Real mode uses authenticated backend operations. Support Dynamic Type, VoiceOver, Reduce Motion, keyboard-visible editing, and narrow/wide layouts. No message should disappear behind the keyboard or be silently truncated.
