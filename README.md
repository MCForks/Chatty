<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset=".github/assets/logo-dark.svg">
    <img src=".github/assets/logo.svg" alt="Chatty" width="420">
  </picture>
</p>

# Chatty (Paper plugin)

[![GitHub release (latest by date)](https://img.shields.io/github/v/release/Brikster/Chatty)](https://github.com/Brikster/Chatty/releases/latest)
[![GitHub All Releases](https://img.shields.io/github/downloads/Brikster/Chatty/total)](https://github.com/Brikster/Chatty/releases)
[![GitHub code size in bytes](https://img.shields.io/github/languages/code-size/Brikster/Chatty)](https://github.com/Brikster/Chatty/archive/master.zip)
[![JitPack](https://jitpack.io/v/Brikster/Chatty.svg)](https://jitpack.io/#Brikster/Chatty)
[![Codacy Badge](https://app.codacy.com/project/badge/Grade/815bf25f21da4c81b9e26bd1159df072)](https://www.codacy.com/gh/Brikster/Chatty/dashboard?utm_source=github.com&amp;utm_medium=referral&amp;utm_content=Brikster/Chatty&amp;utm_campaign=Badge_Grade)

> **Chatty v3** is a ground-up rewrite built on Kyori's Adventure library. It is
> approaching its first stable release (`3.0.0`); this branch holds its code.
>
> - **Stable builds** — the [Releases](https://github.com/Brikster/Chatty/releases) page (once `3.0.0` is tagged).
> - **Development builds** — the latest artifact from the "Actions" tab (see the "Artifacts" section).
>
> Chatty v2.* is deprecated and no longer maintained.
> Upgrading from v2? See [MIGRATION.md](MIGRATION.md) — v3 migrates your old config automatically.

Chatty is the modern chat management system for Paper 26.2 and compatible Paper-based server implementations. It's based on-top of Kyori's Adventure library,
that makes it so powerful and stable.

**Key features**:
- Chat channels ("local" and "global" by default)
- Private messaging
- Moderation (CAPS, advertisements, swears)
- Notifications (chat, action bar and title)
- "Vanilla" messages configuring (join/quit/death)
- MiniMessage both legacy (&) styling format

## Building

Chatty uses Gradle to handle dependencies & building. You need JDK 25 or higher to compile Chatty.

### Compiling from source

```shell script
git clone https://github.com/Brikster/Chatty.git
cd Chatty/
./gradlew build
```

Output jar will be placed into `/build/libs` directory.

## Testing

Run the unit tests:

```shell script
./gradlew test
```

Run the end-to-end smoke test — it boots real Minecraft servers with the built
plugin and verifies that it enables cleanly on Paper 26.2, processes live
in-game chat, correctly migrates a legacy v2 configuration, and coexists with
DiscordSRV:

```shell script
./gradlew build
JAVA_HOME=/path/to/jdk-25 bash scripts/smoke-test.sh
```

Both run automatically on every push via GitHub Actions.
