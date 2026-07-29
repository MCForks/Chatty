#!/usr/bin/env bash
#
# End-to-end smoke test for Chatty.
#
# Boots real Minecraft servers with the built plugin and verifies:
#   A. fresh install       -> the plugin enables, generates configs, and
#                             processes real in-game chat (two bots) cleanly
#   B. legacy v2 migration -> a v2 config.yml is migrated into v3 files
#   C. DiscordSRV coexist  -> Chatty and DiscordSRV initialise cleanly side by
#                             side, with no classloader or dependency clash
#
# Requirements: bash, curl, python3, and a JDK 25 (point JAVA_HOME at it).
# The in-game chat test additionally needs node + npm; without them it is
# skipped.
#
# Build the plugin first (./gradlew build); the workflow does this for CI.
#
# Usage:  JAVA_HOME=/path/to/jdk-25 bash scripts/smoke-test.sh
#
set -euo pipefail

MC_VERSION="${MC_VERSION:-26.2}"
SERVER_PORT="${SERVER_PORT:-25575}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Kept under build/ (git-ignored) so logs survive for inspection / CI artifacts.
WORK="$ROOT/build/smoke-test"
BOT_TOOLS="$ROOT/build/bot-tools"   # cached node_modules for the chat test
SERVER="$WORK/server"
SERVER_PID=""
HOLDER_PID=""
PIPE_DIR=""
STDIN_PIPE=""

JAVA_BIN="java"
if [ -n "${JAVA_HOME:-}" ]; then
    JAVA_BIN="$JAVA_HOME/bin/java"
    [ -x "$JAVA_BIN.exe" ] && JAVA_BIN="$JAVA_BIN.exe"
fi

cleanup() {
    if [ -n "$SERVER_PID" ]; then
        kill -9 "$SERVER_PID" 2>/dev/null || true
    fi
    if [ -n "$HOLDER_PID" ]; then
        kill "$HOLDER_PID" 2>/dev/null || true
    fi
    if [ -n "$PIPE_DIR" ]; then
        rm -rf "$PIPE_DIR"
    fi
    return 0
}
trap cleanup EXIT

rm -rf "$WORK"
mkdir -p "$WORK"

step() { printf '\n\033[1m=== %s ===\033[0m\n' "$1"; }
fail() { printf '\n\033[31m✗ SMOKE TEST FAILED: %s\033[0m\n' "$*" >&2; exit 1; }

# Downloads the newest stable Paper build for a version, or the newest
# available build when the requested version is still experimental.
# $1 = version, $2 = output jar.
download_paper() {
    local version="$1" out="$2" response url build
    response="$(curl -fsSL \
        -H "User-Agent: Chatty-smoke-test/3.0 (https://github.com/Brikster/Chatty)" \
        "https://fill.papermc.io/v3/projects/paper/versions/$version/builds")"
    readarray -t paper_build < <(printf '%s' "$response" | python3 -c '
import json, sys
builds = json.load(sys.stdin)
build = next((item for item in builds if item["channel"] == "STABLE"), builds[0])
print(build["id"])
print(build["downloads"]["server:default"]["url"])
' | tr -d '\r')
    build="${paper_build[0]}"
    url="${paper_build[1]}"
    curl -fsSL \
        -H "User-Agent: Chatty-smoke-test/3.0 (https://github.com/Brikster/Chatty)" \
        -o "$out" "$url"
    echo "Paper $version build $build"
}

# Downloads the latest DiscordSRV release jar.  $1 = output jar.
# Returns non-zero if it cannot be fetched (the scenario is then skipped).
download_discordsrv() {
    local out="$1" url
    url="$(curl -fsSL "https://api.github.com/repos/DiscordSRV/DiscordSRV/releases/latest" \
        | python3 -c 'import sys, json; print(next(a["browser_download_url"] for a in json.load(sys.stdin)["assets"] if a["name"].endswith(".jar")))' \
        | tr -d '\r')" || return 1
    [ -n "$url" ] || return 1
    curl -fsSL -o "$out" "$url" || return 1
    echo "DiscordSRV: ${url##*/}"
}

# --- locate the plugin jar -------------------------------------------------

JAR="$(ls -t "$ROOT"/build/libs/Chatty-*.jar 2>/dev/null | head -1 || true)"
[ -n "$JAR" ] || fail "plugin jar not found in build/libs — run ./gradlew build first"
echo "Plugin jar: $JAR"
"$JAVA_BIN" -version 2>&1 | head -1

# The in-game chat test needs Node.js. Use the system one, or fetch a local
# copy under build/ so the test runs anywhere without a system install.
CHAT_TEST=1
if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; then
    node_os=""; node_arch=""
    case "$(uname -s)" in Darwin) node_os=darwin;; Linux) node_os=linux;; esac
    case "$(uname -m)" in arm64 | aarch64) node_arch=arm64;; x86_64 | amd64) node_arch=x64;; esac
    if [ -n "$node_os" ] && [ -n "$node_arch" ]; then
        NODE_VERSION=20.18.1
        NODE_DIR="$BOT_TOOLS/node-v$NODE_VERSION-$node_os-$node_arch"
        if [ ! -x "$NODE_DIR/bin/node" ]; then
            step "Downloading Node.js $NODE_VERSION (for the in-game chat test)"
            mkdir -p "$BOT_TOOLS"
            curl -fsSL "https://nodejs.org/dist/v$NODE_VERSION/node-v$NODE_VERSION-$node_os-$node_arch.tar.gz" \
                | tar -xz -C "$BOT_TOOLS"
        fi
        export PATH="$NODE_DIR/bin:$PATH"
    fi
fi
if ! command -v node >/dev/null 2>&1; then
    CHAT_TEST=0
    echo "Node.js unavailable — the in-game chat test will be skipped"
fi

# --- download Paper --------------------------------------------------------

step "Downloading Paper $MC_VERSION"
PAPER_JAR="$WORK/paper.jar"
download_paper "$MC_VERSION" "$PAPER_JAR"

# --- server scaffolding ----------------------------------------------------

mkdir -p "$SERVER/plugins"
echo "eula=true" > "$SERVER/eula.txt"
cat > "$SERVER/server.properties" <<EOF
online-mode=false
level-type=flat
spawn-protection=0
max-players=10
server-port=$SERVER_PORT
EOF
cp "$JAR" "$SERVER/plugins/Chatty.jar"

# Computes the offline-mode UUID of a username (UUID.nameUUIDFromBytes).
offline_uuid() {
    node -e 'const c=require("crypto");const h=c.createHash("md5").update("OfflinePlayer:"+process.argv[1]).digest();h[6]=(h[6]&0x0f)|0x30;h[8]=(h[8]&0x3f)|0x80;const x=h.toString("hex");console.log(`${x.slice(0,8)}-${x.slice(8,12)}-${x.slice(12,16)}-${x.slice(16,20)}-${x.slice(20)}`);' "$1"
}

if [ "$CHAT_TEST" -eq 1 ]; then
    # OP the test bots so they have chatty.* permissions (mentions etc.).
    cat > "$SERVER/ops.json" <<EOF
[
  {"uuid":"$(offline_uuid SmokeSender)","name":"SmokeSender","level":4,"bypassesPlayerLimit":false},
  {"uuid":"$(offline_uuid SmokeTarget)","name":"SmokeTarget","level":4,"bypassesPlayerLimit":false}
]
EOF
    if [ ! -d "$BOT_TOOLS/node_modules/mineflayer" ]; then
        step "Installing mineflayer (for the chat test)"
        mkdir -p "$BOT_TOOLS"
        (cd "$BOT_TOOLS" && npm install --no-fund --no-audit --loglevel=error mineflayer >/dev/null)
    fi
    if ! NODE_PATH="$BOT_TOOLS/node_modules" node -e \
            'process.exit(require("minecraft-data")(process.argv[1]) ? 0 : 1)' "$MC_VERSION"; then
        CHAT_TEST=0
        echo "Mineflayer does not support Minecraft $MC_VERSION yet — the in-game chat test will be skipped"
    fi
fi

# Boots the server and waits for full startup, leaving it running.
# $1 = path to write the server log to.
start_server() {
    local logfile="$1"
    local paper_java_path="$PAPER_JAR"
    if [[ "$JAVA_BIN" == *.exe ]] && command -v wslpath >/dev/null 2>&1; then
        paper_java_path="$(wslpath -w "$PAPER_JAR")"
    fi
    PIPE_DIR="$(mktemp -d)"
    STDIN_PIPE="$PIPE_DIR/stdin.pipe"
    mkfifo "$STDIN_PIPE"
    sleep 1800 > "$STDIN_PIPE" &
    HOLDER_PID=$!
    ( cd "$SERVER" && exec "$JAVA_BIN" -Xmx1G -jar "$paper_java_path" nogui ) \
        < "$STDIN_PIPE" > "$logfile" 2>&1 &
    SERVER_PID=$!

    local ready=0 i
    for ((i = 0; i < 240; i++)); do
        if grep -q 'Done (' "$logfile" 2>/dev/null; then ready=1; break; fi
        kill -0 "$SERVER_PID" 2>/dev/null || break
        sleep 1
    done
    [ "$ready" -eq 1 ] || { tail -40 "$logfile" >&2; fail "server did not finish startup"; }
}

# Stops the running server cleanly.
stop_server() {
    echo "stop" > "$STDIN_PIPE" 2>/dev/null || true
    local i
    for ((i = 0; i < 60; i++)); do
        kill -0 "$SERVER_PID" 2>/dev/null || break
        sleep 1
    done
    kill -9 "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
    kill "$HOLDER_PID" 2>/dev/null || true
    rm -rf "$PIPE_DIR"
    SERVER_PID=""
    HOLDER_PID=""
    PIPE_DIR=""
    STDIN_PIPE=""
}

# Verifies a plugin enabled without a fatal error.
# $1 = plugin name, $2 = log, $3 = allow a later disable (default: false).
assert_plugin_enabled() {
    local name="$1" logfile="$2" allow_disable="${3:-false}"
    grep -q "Enabling $name" "$logfile" || { tail -40 "$logfile" >&2; fail "$name was not enabled"; }
    if grep -qE "Error occurred while enabling $name|Could not load .plugins.$name" "$logfile"; then
        grep -nE "$name|Exception|SEVERE" "$logfile" | tail -40 >&2
        fail "$name failed to enable"
    fi
    if [ "$allow_disable" != "true" ] && grep -q "Disabling $name" "$logfile"; then
        grep -nE "$name|Exception|ERROR|SEVERE" "$logfile" | tail -40 >&2
        fail "$name was disabled during startup"
    fi
}

# Verifies Chatty enabled without errors. $1 = server log.
assert_enabled() { assert_plugin_enabled "Chatty" "$1"; }

# Portable replacement for `timeout`, which is absent on macOS.
run_with_timeout() {
    local seconds="$1"; shift
    "$@" &
    local pid=$! i
    for ((i = 0; i < seconds; i++)); do
        if ! kill -0 "$pid" 2>/dev/null; then
            if wait "$pid"; then return 0; else return $?; fi
        fi
        sleep 1
    done
    kill -9 "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    return 124
}

# Waits until a log contains a pattern. $1 = log, $2 = ERE, $3 = seconds.
wait_for_log_pattern() {
    local logfile="$1" pattern="$2" seconds="$3" i
    for ((i = 0; i < seconds; i++)); do
        if grep -qiE "$pattern" "$logfile"; then
            return 0
        fi
        if [ -n "$SERVER_PID" ] && ! kill -0 "$SERVER_PID" 2>/dev/null; then
            return 1
        fi
        sleep 1
    done
    return 1
}

# Connects two bots and sends real chat through the plugin. $1 = server log.
run_chat_test() {
    local logfile="$1"
    step "Sending in-game chat through the plugin"
    if ! run_with_timeout 200 env \
            NODE_PATH="$BOT_TOOLS/node_modules" BOT_HOST=127.0.0.1 BOT_PORT="$SERVER_PORT" \
            node "$ROOT/scripts/chat-test.js"; then
        tail -40 "$logfile" >&2
        fail "in-game chat test failed"
    fi
    if grep -q "Cannot handle chat event" "$logfile"; then
        grep -nE "Cannot handle chat event|Exception" "$logfile" | tail -20 >&2
        fail "Chatty logged a chat-processing error while bots were chatting"
    fi
    echo "✓ chat pipeline processed real in-game messages without errors"
}

# --- scenario A: fresh install + live chat ---------------------------------

step "Scenario A — fresh install"
rm -rf "$SERVER/plugins/Chatty" "$SERVER"/plugins/Chatty_old_*
FRESH_LOG="$WORK/fresh.log"
start_server "$FRESH_LOG"
assert_enabled "$FRESH_LOG"
[ -f "$SERVER/plugins/Chatty/settings.yml" ]     || fail "settings.yml was not generated"
[ -f "$SERVER/plugins/Chatty/chats.yml" ]        || fail "chats.yml was not generated"
[ -f "$SERVER/plugins/Chatty/lang/en-US.yml" ]   || fail "lang/en-US.yml was not generated"
[ -f "$SERVER/plugins/Chatty/lang/ru-RU.yml" ]   || fail "bundled lang/ru-RU.yml was not copied"
grep -q "Игрок" "$SERVER/plugins/Chatty/lang/ru-RU.yml" || fail "lang/ru-RU.yml has no Russian content"
echo "✓ plugin enables and generates config (incl. lang files) on a fresh install"
if [ "$CHAT_TEST" -eq 1 ]; then
    run_chat_test "$FRESH_LOG"
else
    echo "• in-game chat test skipped (node/npm not available)"
fi
stop_server

# --- scenario B: legacy v2 migration ---------------------------------------

step "Scenario B — legacy v2 migration"
rm -rf "$SERVER/plugins/Chatty" "$SERVER"/plugins/Chatty_old_*
mkdir -p "$SERVER/plugins/Chatty"
cp "$ROOT/scripts/fixtures/v2-config.yml" "$SERVER/plugins/Chatty/config.yml"
MIGRATE_LOG="$WORK/migrate.log"
start_server "$MIGRATE_LOG"
assert_enabled "$MIGRATE_LOG"

grep -q "Migrating legacy Chatty v2 configuration" "$MIGRATE_LOG" || fail "migration did not start"
grep -q "Legacy configuration migrated"           "$MIGRATE_LOG" || fail "migration did not finish"
! grep -q "Failed to migrate legacy configuration" "$MIGRATE_LOG" || fail "migration threw an exception"
! grep -q "could not be migrated automatically"    "$MIGRATE_LOG" || fail "a config file failed to migrate"

ls -d "$SERVER"/plugins/Chatty_old_* >/dev/null 2>&1 || fail "v2 backup folder was not created"

CHATS="$SERVER/plugins/Chatty/chats.yml"
SETTINGS="$SERVER/plugins/Chatty/settings.yml"
MODERATION="$SERVER/plugins/Chatty/moderation.yml"
PM="$SERVER/plugins/Chatty/pm.yml"

# These also prove okaeri reloaded the migrated YAML without rejecting it:
# the values survive the migrator write -> okaeri load -> okaeri re-save.
grep -q "MIGRATED_MARKER" "$CHATS"     || fail "chat format was not migrated into chats.yml"
grep -q "HIGHEST"         "$SETTINGS"  || fail "listener-priority was not migrated"
grep -q "IP_PATTERN_X"    "$MODERATION" || fail "advertisement ip pattern was not migrated"
grep -q "from-name"       "$PM"        || fail "PM format placeholders were not migrated"
if grep -q "disabled_chat" "$CHATS"; then fail "a disabled v2 chat was migrated"; fi

echo "✓ legacy v2 config migrated and reloaded successfully"
stop_server

echo
grep -E "\[Chatty\].*(Migrat|migrat|review|-)" "$MIGRATE_LOG" || true

# --- scenario C: DiscordSRV coexistence ------------------------------------

step "Scenario C — DiscordSRV coexistence"
if download_discordsrv "$WORK/DiscordSRV.jar"; then
    rm -rf "$SERVER/plugins/Chatty" "$SERVER"/plugins/Chatty_old_* "$SERVER/plugins/DiscordSRV"
    cp "$JAR" "$SERVER/plugins/Chatty.jar"
    cp "$WORK/DiscordSRV.jar" "$SERVER/plugins/DiscordSRV.jar"
    # A syntactically valid but fake bot token makes DiscordSRV run its full
    # init (config, listeners) before stopping at the Discord connection step.
    # DiscordSRV shuts itself down on any token that is not a real one, so it
    # cannot stay enabled in CI; the test therefore verifies the two plugins
    # initialise cleanly side by side — no classloader/dependency clash and
    # neither breaks the other's startup — which is all that is checkable
    # without a real Discord bot token.
    mkdir -p "$SERVER/plugins/DiscordSRV"
    cat > "$SERVER/plugins/DiscordSRV/config.yml" <<'EOF'
BotToken: "MTI3NzAwMDAwMDAwMDAwMDAwMA.GfABCD.thisIsAFakeDiscordSrvSmokeTestTokenNotReal"
EOF
    COEXIST_LOG="$WORK/discordsrv.log"
    start_server "$COEXIST_LOG"

    # DiscordSRV validates the token asynchronously after Paper reports that
    # startup is complete. Wait for either the expected validation result or
    # an incompatibility error instead of racing the background login task.
    assert_plugin_enabled "DiscordSRV" "$COEXIST_LOG" true
    if ! wait_for_log_pattern "$COEXIST_LOG" \
            "bot token is invalid|NoClassDefFoundError|NoSuchMethodError|LinkageError|IncompatibleClassChangeError" 30; then
        tail -40 "$COEXIST_LOG" >&2
        fail "DiscordSRV did not reach the expected token validation step"
    fi
    assert_plugin_enabled "Chatty" "$COEXIST_LOG"
    if grep -qE "NoClassDefFoundError|NoSuchMethodError|LinkageError|IncompatibleClassChangeError" "$COEXIST_LOG"; then
        grep -nE "NoClassDefFoundError|NoSuchMethodError|LinkageError|IncompatibleClassChangeError" "$COEXIST_LOG" | tail -20 >&2
        fail "classloader/dependency clash with Chatty and DiscordSRV installed together"
    fi
    echo "✓ Chatty and DiscordSRV initialise cleanly side by side (no classloader clash)"
    if [ "$CHAT_TEST" -eq 1 ]; then
        run_chat_test "$COEXIST_LOG"
    else
        echo "• in-game chat test skipped (node/npm not available)"
    fi
    stop_server
    rm -f "$SERVER/plugins/DiscordSRV.jar"
else
    echo "• DiscordSRV scenario skipped (could not download DiscordSRV)"
fi

printf '\n\033[32m✓ SMOKE TEST PASSED\033[0m\n'
