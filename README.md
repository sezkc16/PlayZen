# PlayZen — Free Video Player for iOS

**PlayZen** ek original iOS video player hai — OutPlayer jaisi features, lekin **sab kuch free, bina ads, bina paywall**.

> ✅ Naam final hai: **PlayZen** — logo / app icon abhi banna baaki hai.

## Kya hai v1 me (sab FREE)

- **Library** — Documents folder ki videos, search, filter chips (All / Movies / Shorts / Favorites), Continue Watching
- **Player** — play/pause, seek bar, ±10s skip, 3 second me auto-hide controls
- **Playback Speed** — 0.25× se 3× tak (sach me `player.rate` set hota hai)
- **Volume Boost** — slider 0–200% (note: AVPlayer ka volume max 1.0 hota hai, isliye 100% ke upar "BOOST" badge dikhta hai; asli >100% loudness v2 me audio processing se aayega — kuch fake nahi kiya gaya)
- **Subtitles** — `.srt` file video ke same naam se rakhne pe load hoti hai; nahi mili to sample English + Hindi lines dikhte hain; size Small / Medium / Large
- **Chapters** — Intro / Main / Midpoint / Finale, tap karke jump karo
- **Picture in Picture** — floating window me video chalti rahe
- **Playlists** — banao, rename karo, delete karo, video add karo (UserDefaults me save hoti hain)
- **Files** — Import (Document Picker), rename, delete, share; Files app se bhi videos copy kar sakte ho (`UIFileSharingEnabled` ON hai)
- **Auto-Resume** — band ki hui video wahi se dobara chalti hai

## Kya NAHI hai v1 me (saaf-saaf)

- **MKV playback nahi chalega** — AVPlayer MKV support nahi karta. MKV files Library me dikhengi, lekin tap karne pe saaf message milega. MKV ke liye **VLCKit v2 me** aayega.
- **SMB / network folders nahi hain** — v2 me plan hai.
- **Light Mode nahi hai** — v1 dark-only hai.
- App icon abhi blank hai — `app/Assets.xcassets/AppIcon.appiconset/` me apni 1024×1024 PNG daal ke `Contents.json` me filename add karna hoga (warna Xcode default icon use karega).

## GitHub se IPA kaise banaye (converter app jaisa hi flow)

### Step 1 — Naya repo banao
1. GitHub pe jao → **New repository**
2. Naam: `playzen` (private ya public, dono chalega)
3. **Create repository** dabao

### Step 2 — Files upload karo
Is folder ki **saari files** (project.yml, app/, .github/, README.md) repo me upload karo:
- GitHub web se: **Add file → Upload files** (`.github` folder upload karne ke liye zip karke upload karna aasan rahega, ya git use karo)
- Ya PC se git:
  
