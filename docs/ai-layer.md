# The AI layer

Short version. Claude Code lives inside the Fedora. A scheduler over in Termux pokes it every fifteen minutes, and the body app is how it touches the phone. Most of what's below is stuff that went wrong first and then got fixed.

## Claude Code inside the proot

Installed with the normal installer, nothing clever. Inside the proot it gets bash, git, python, node, curl, a JDK, gcc, and a filesystem that belongs to it.

I start it through a small wrapper that just sets up the environment. PATH gets the Fedora directories first and Termux's `bin` at the end, so the agent calls Fedora tools normally but can still reach a Termux-only one when it has to. There's a `CLAUDE.md` in the home directory telling it where it is, what it can't reach from in there, and the rule further down this page.

It runs with permissions off, same reasoning as in the setup guide.

## Two namespaces, one phone

This is the thing that catches everyone. A `termux-*` command run from inside the container exits 0 and does absolutely nothing, then pops a "Termux:API Error" notification on my actual screen. Every time. Those commands only work in Termux proper.

So there's a bridge. `tx <command>` from inside the proot runs the command over in Termux instead. The one on my phone has two ways across, a Unix socket that proot mounts at the same path on both sides plus ssh to `127.0.0.1:8022`, because sshd keeps dying and one transport wasn't enough. The ssh half is three lines and it's in this repo as [scripts/tx](../scripts/tx), key setup written at the top.

Once the agent learned to type `tx termux-battery-status` that just stopped being a problem.

## Headless, when nobody's looking

`claude -p "..."` runs one prompt, prints the answer, exits. That's all there is to it. Stick it in a script and schedule the script, and there's no terminal open anywhere.

Scheduling is `termux-job-scheduler`, which is Android's own JobScheduler handed to the shell:

```sh
termux-job-scheduler --script ~/tick.sh --period-ms 900000 --persisted true --network any
termux-job-scheduler --pending      # check it actually registered
```

The tick script is deliberately dumb. Mine is longer but this is the shape, and the point is that the cheap check happens in bash and the model only gets woken when there's a reason:

```sh
#!/data/data/com.termux/files/usr/bin/bash
# ~/tick.sh - every 15 minutes, decide whether anything deserves a model call
termux-wake-lock
pgrep -x sshd >/dev/null || sshd      # the memory killer eats it every few days

TOK=$(cat ~/.config/body/bridge_token)
SEEN=$(cat ~/.tick-highwater 2>/dev/null || echo 0)
# newest post_time in the tray, and how many landed since the last tick
read -r LATEST NEW <<<"$(curl -s -H "Authorization: Bearer $TOK" \
  'http://127.0.0.1:8765/notifications?limit=50' | SEEN=$SEEN python3 -c '
import sys, json, os
seen = int(os.environ["SEEN"])
n = json.load(sys.stdin).get("notifications", [])
times = [x.get("post_time", 0) for x in n]
print(max(times + [seen]), sum(1 for t in times if t > seen))')"
[ "${NEW:-0}" -gt 0 ] || exit 0          # nothing new, go back to sleep, costs nothing
echo "$LATEST" > ~/.tick-highwater

proot-distro login fedora -- /root/.local/bin/claude -p \
  "There are $NEW notifications. Read them through the body bridge and handle anything urgent." \
  >> ~/tick.log 2>&1
echo "$(date -Iseconds) fired new=$NEW" >> ~/tick-fires.log
```

Log every fire. When the job silently stops, that log is how you find out.

## What ran on it

For a couple of months this ran a companion agent I called Toph. It watched notifications and kept a log of the day. It could answer me through a chat bridge, and it roasted me about my phone use and nagged me to charge the thing. It used the body to actually go and do stuff.

It ended up at a few thousand commits and it's not going public, because it's mostly a model of my life and that's the entire point of it. The machinery it ran on is public though, that's this repo and the body.

I tried the Hermes agent framework for a while too and the body still ships a plugin and a skill for it. Claude Code is what I actually use.

## The body

[the-body](https://github.com/beqa-beridze/the-body) is an Android app I wrote to fix the obvious hole. The agent has a whole Linux and still can't see the phone it's running on or touch a single thing on it. Termux:API does maybe a third of what's needed and half of that doesn't work from inside the container anyway.

So the body does it properly, as a normal Android app. An accessibility service turns the live screen into a list of elements, each with a number on it. There's a notification listener too. Everything comes out of a small HTTP server on `127.0.0.1:8765`, loopback only, token required, so the agent runs `body screen` and gets back something it can actually reason about.

What it's taught is to look at the screen, use an id from that same look, and check again afterwards, and to give up when the app says nothing moved. Ids carry the read they came from, so a stale one gets refused instead of guessed at. Anything with an effect outside the phone, sending a text or answering a message, takes a two step confirmation that ties a token to the exact recipient and the exact text. It can't send something it didn't show me first.

The whole app gets built on the phone, in the proot, with no Android Studio anywhere near it. That story is in its own README.

## The one rule

I don't give agents a big list of rules. There's one, and it's there because the agent dialled someone while I was holding the phone.

**Never take over my real screen. Use the background layer. If something genuinely can't be done in the background, ask me, and keep asking until I answer. No answer means no.**

The background layer is everything the body can do without moving the visible screen. Reading, notifications, inline replies, working on a hidden display. The asking bit is `/ask`. It puts a question on my lock screen with two buttons and keeps bothering me until one of them gets pressed, and it's built so it can't be used for anything but that. One pending at a time, six an hour, times itself out.

That came out of a proper failure. For weeks the asking went through Termux:API's notification, and that channel is created at minimum importance, so it never made a sound and never showed up as a heads-up. The only alarm in the whole system was silent and I didn't notice for weeks. An app can't raise its own channel importance afterwards either, so I moved the alarm into the body, on a channel it creates itself at high importance.

## What broke

Useful part if you're building something like this.

The low memory killer takes Termux out every few days and sshd goes with it. That one I knew about. What I didn't know is that nothing was watching, and one time it stayed down for eleven days before I noticed. My one way in had no backup and I found that out by losing it.

Then the scheduled job that was supposed to catch that stopped firing for over a week, while still showing up as registered and persisted. Persisted apparently doesn't mean persisted. It re-registers on every boot now and writes a line every time it runs, which is the only reason I'd catch it a second time.

adb over loopback dies on every reboot and no app can bring it back on its own. Everything that shelled out to `adb` got rewritten to go through the body instead. adb is a one-time setup step now and nothing depends on it staying up.

Stale ids were the subtle one. Reading the screen was never hard. Acting on an id from a read that had already gone stale is how it ended up tapping the wrong thing, so ids now carry the generation they came from and the app refuses an old one rather than guessing.
