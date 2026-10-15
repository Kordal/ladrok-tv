"""Bring the Ladrok Discord server in line with server.json.

  python admin.py plan    # print the server's current state and what would change
  python admin.py apply   # make the changes

Needs DISCORD_BOT_TOKEN (the Ladrok Admin bot) in the environment. Standard library only.
"""

import json
import os
import pathlib
import sys
import time
import urllib.error
import urllib.request

API = "https://discord.com/api/v10"
TOKEN = os.environ.get("DISCORD_BOT_TOKEN", "")
CONFIG = json.loads((pathlib.Path(__file__).parent / "server.json").read_text())
CHANNEL_TYPES = {0: "text", 2: "voice", 4: "category", 5: "announcement", 13: "stage", 15: "forum"}
ADMINISTRATOR = 1 << 3


def api(method, path, body=None):
    for _ in range(5):
        req = urllib.request.Request(
            API + path,
            method=method,
            data=json.dumps(body).encode() if body is not None else None,
            headers={
                "Authorization": "Bot " + TOKEN,
                "Content-Type": "application/json",
                "User-Agent": "DiscordBot (https://github.com/Kordal/ladrok-tv, 1)",
                "X-Audit-Log-Reason": "ladrok-tv discord-admin workflow",
            },
        )
        try:
            with urllib.request.urlopen(req) as resp:
                data = resp.read()
                return json.loads(data) if data else None
        except urllib.error.HTTPError as err:
            if err.code == 429:
                time.sleep(float(json.loads(err.read() or b"{}").get("retry_after", 1)) + 0.2)
                continue
            raise SystemExit(f"::error::{method} {path} failed: HTTP {err.code} {err.read().decode()[:300]}")
    raise SystemExit(f"::error::{method} {path} kept hitting the rate limit")


def pinned_messages(channel_id):
    # Newer pins endpoint, falling back to the older one.
    try:
        return [item["message"] for item in api("GET", f"/channels/{channel_id}/messages/pins")["items"]]
    except SystemExit:
        return api("GET", f"/channels/{channel_id}/pins")


def show(label, text):
    print(f"    {label}: " + (text.replace("\n", "\n      ") if text else "(none)"))


def main(mode):
    if not TOKEN:
        raise SystemExit("::error::DISCORD_BOT_TOKEN secret is missing")
    me = api("GET", "/users/@me")
    guilds = api("GET", "/users/@me/guilds")
    if len(guilds) != 1:
        raise SystemExit(f"::error::Expected the bot in exactly one server, found {len(guilds)}")
    guild = api("GET", f"/guilds/{guilds[0]['id']}?with_counts=true")
    channels = sorted(api("GET", f"/guilds/{guild['id']}/channels"), key=lambda c: (c["type"] == 4, c["position"]))
    roles = {r["id"]: r for r in api("GET", f"/guilds/{guild['id']}/roles")}
    member = api("GET", f"/guilds/{guild['id']}/members/{me['id']}")
    by_name = {c["name"]: c for c in channels}

    print(f"== Server: {guild['name']} ({guild.get('approximate_member_count', '?')} members)")
    print(f"   description: {guild.get('description') or '(none)'}")
    print(f"   bot: {me['username']}, roles: {', '.join(roles[r]['name'] for r in member['roles']) or '(none)'}")
    bot_perms = int(roles[guild["id"]]["permissions"])
    for r in member["roles"]:
        bot_perms |= int(roles[r]["permissions"])
    if bot_perms & ADMINISTRATOR:
        print("   ::warning::Bot has Administrator. It only needs Manage Channels, Send Messages, Embed Links, Manage Messages and Read Message History.")
    print("\n== Channels")
    for c in channels:
        overwrites = ", ".join(
            f"{roles.get(o['id'], {'name': 'member ' + o['id']})['name']} deny={o['deny']} allow={o['allow']}"
            for o in c.get("permission_overwrites", [])
        )
        print(f"  #{c['name']} [{CHANNEL_TYPES.get(c['type'], c['type'])}]")
        if c["type"] in (0, 5, 15):
            show("topic", c.get("topic"))
        if overwrites:
            print(f"    overrides: {overwrites}")
        if c["type"] in (0, 5):
            for m in pinned_messages(c["id"]):
                show(f"pinned by {m['author']['username']}", m["content"][:300])

    def render(text):
        for name, c in by_name.items():
            text = text.replace("{#" + name + "}", f"<#{c['id']}>")
        return text

    print(f"\n== Changes ({mode})")
    changes = 0
    for name, wanted in CONFIG.get("channels", {}).items():
        c = by_name.get(name)
        if not c:
            print(f"::warning::#{name} is in server.json but not on the server; skipped")
            continue
        topic = render(wanted["topic"])
        if (c.get("topic") or "") != topic:
            changes += 1
            print(f"  #{name}: set topic")
            if mode == "apply":
                api("PATCH", f"/channels/{c['id']}", {"topic": topic})

    for name, content in CONFIG.get("pins", {}).items():
        c = by_name.get(name)
        if not c:
            print(f"::warning::#{name} is in server.json but not on the server; skipped")
            continue
        content = render(content)
        # The bot owns at most one pin per channel; that pin is the managed one.
        mine = [m for m in pinned_messages(c["id"]) if m["author"]["id"] == me["id"]]
        if mine and mine[0]["content"] == content:
            continue
        changes += 1
        print(f"  #{name}: {'update' if mine else 'post and pin'} welcome message")
        if mode == "apply":
            if mine:
                api("PATCH", f"/channels/{c['id']}/messages/{mine[0]['id']}", {"content": content})
            else:
                msg = api("POST", f"/channels/{c['id']}/messages", {"content": content, "allowed_mentions": {"parse": []}})
                api("PUT", f"/channels/{c['id']}/messages/pins/{msg['id']}")

    print(f"  {changes} change(s)" + (" applied" if mode == "apply" and changes else ""))


if __name__ == "__main__":
    if len(sys.argv) != 2 or sys.argv[1] not in ("plan", "apply"):
        raise SystemExit(__doc__)
    main(sys.argv[1])
