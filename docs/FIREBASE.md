# Firebase setup

The game talks to Firebase over REST (no SDK): Identity Toolkit for accounts and
Firestore for profiles and the public battle list. Without configuration the game
runs fully offline with a local profile.

1. Create a Firebase project and enable **Authentication → Anonymous** and
   **Email/Password** sign-in.
2. Create a **Firestore** database (production mode) and paste
   `firebase/firestore.rules` into its rules.
3. In GitHub → Settings → Secrets and variables → Actions add:
   - `FIREBASE_API_KEY` — the Web API key (Project settings → General).
   - `FIREBASE_PROJECT_ID` — the project id.

CI writes them to `config/firebase.json` at build time; the file is never committed.

Data:

| Path | Contents |
| --- | --- |
| `players/{uid}` | Callsign, level, XP, career stats, settings. Owner read/write only. |
| `lobbies/{uid}` | Public battle advert (name, IP, port, players, version, heartbeat). Anyone signed in can read; only the host writes. |

## Android signing

Releases are signed with `ci/release.keystore` (public password, fine for
sideloading). To use a private key, add `ANDROID_KEYSTORE_BASE64`,
`ANDROID_KEYSTORE_PASSWORD` and `ANDROID_KEY_ALIAS` secrets. Switching keys means
players reinstall once, because Android only updates apps signed with the same key.
