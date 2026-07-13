# Echonix Android

A premium, full-stack music player application built with **Flutter** (Frontend) and backed by **Python (Chaquopy)** embedded directly inside the Android package.

## 🚀 Key Features
- **Embedded Python Backend**: Powered by `ytmusicapi` and `yt-dlp` running inside the Android process via Chaquopy—no external server needed.
- **Modern UI/UX**: Built with Flutter and state management using Riverpod.
- **Offline Mode**: Downloads songs to local storage as MP3s with full metadata mapping via mutagen.
- **Lockscreen & Background Play**: Integrated with `just_audio` and `just_audio_background`.
- **Lyrics Integration**: Automated LRC and plain text lyric syncing via LRCLib API.

## 👥 Authors & Roles
- **Tharun Revinth** — Founder & Lead Contributor

## 🛠️ Tech Stack
- **Frontend**: Flutter & Riverpod
- **Audio Core**: `just_audio` / `just_audio_background`
- **Bridge**: Chaquopy (Dart-Python bridge)
- **Local Database**: Hive
