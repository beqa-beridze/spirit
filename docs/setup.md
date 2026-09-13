# Building it yourself

Everything here was run on a Galaxy S26 Ultra on Android 16. The Termux and proot parts work the same on any arm64 Android. Other phones hide the Samsung switches somewhere else, and some don't have them at all. Lucky them.

About 20 minutes on this phone and only about three of those are the machine doing anything, the rest is you clicking through Android settings. A bare Fedora container is 207 MB. With the packages below plus Claude Code it's 797 MB. Mine is 62 GB now but that's models and junk I put there.

## 1. Termux, from F-Droid

Not from the Play Store. That build is years old and can't be updated, and half of what's below will fail on it. Install [F-Droid](https://f-droid.org) first, then from inside F-Droid:

- **Termux**, the actual terminal.
- Termux:Boot runs scripts after a reboot.
- Termux:Widget puts shortcuts on the home screen. That's the one-tap open-Claude button later on.
- Termux:API lets scripts talk to Android. Notifications, battery, clipboard, the job scheduler and whatnot.

All four have to come from the same source because they share a signing key. Open Termux once so it unpacks itself, then:

```sh
pkg update && pkg upgrade
termux-setup-storage        # asks for the storage permission
pkg install proot-distro openssh tmux git termux-api unzip python
```

Now the Android side, and don't skip this, it's what decides whether any of it survives the screen turning off:

- Settings, Apps, Termux, Battery, set it to **Unrestricted**. Do the same for Termux:Boot and Termux:API.
- Samsung only: Settings, Security and privacy, **Auto Blocker off**. It blocks sideloaded apps from a lot of what they need.
- In `~/.termux/termux.properties` set `allow-external-apps=true`, then run `termux-reload-settings`. The home screen widgets in step 5 need it, and so does the body app later if you get that far.

## 2. Fedora under proot

```sh
proot-distro install fedora     # pulls the Fedora image, a few minutes on a first run
proot-distro login fedora       # you are now root in a Fedora
```

That's the whole install. If you read an older guide you'll get confused by `proot-distro list`. In 5.x it shows what you've already installed. I kept waiting for a list of available distros and there just isn't one any more, it installs from container images instead, so `proot-distro install ubuntu:24.04` or `debian` or `alpine` all work the same way. `-n somename` gives the container a different name if you want two of them.

First things once you're inside. Either run the script from this repo, which does the rest of this step and the whole of step 3 for you:

```sh
curl -fsSL https://raw.githubusercontent.com/beqa-beridze/spirit/main/scripts/fedora-setup.sh | bash
```

or do it by hand and read the rest of this section:

```sh
dnf -y install zsh tmux git curl python3 nodejs npm fastfetch openssh-clients
```

That took 1 minute 37 on this phone. Type `exit` to drop back to Termux, and `proot-distro login fedora` to go back in. The state persists, it's just a directory.

Weird one, worth knowing early. Before you install Fedora's own python, `command -v python3` inside the container answers `/data/data/com.termux/files/usr/bin/python3`. Termux's binaries are visible inside the container through the inherited PATH, so you can quietly end up running Termux's copy of something instead of Fedora's. That's actually useful later, but it got me once.

Check it worked:

```sh
fastfetch          # should say Fedora Linux 44, aarch64
uname -r           # says 6.17.0-PRoot-Distro, which isn't true. proot fakes it so old-kernel checks pass
dnf --version
```

## 3. Claude Code inside the proot

Still inside the container:

```sh
curl -fsSL https://claude.ai/install.sh | bash     # lands in ~/.local/bin/claude
claude
```

58 seconds on this phone. The first run wants you to log in and prints a URL. There's no browser inside the proot, so copy the URL, open it on the phone, and paste the code back into the terminal. After that `claude` works from anywhere in the Fedora.

I run it with permission checks off, because the container is already the sandbox. It can't reach the Android system, and worst case it trashes a Fedora I can pull down again in one command. That's fine for something I can throw away. Do whatever you want on yours.

Check it worked: `claude --version`.

## 4. ssh in from a real computer

This is what makes the thing actually bearable to use.

```sh
# in Termux, not in the container
passwd                 # sets the password ssh will ask for
sshd                   # listens on 8022
```

For the phone's address, the reliable way is Settings, About phone, Status, IP address. In the terminal it's more annoying than it should be: `ip addr` doesn't work at all, Android blocks netlink for app UIDs, and `ifconfig wlan0` fails too because on this Samsung the interface is called `swlan0`. Bare `ifconfig` with no arguments does list everything, if you `pkg install net-tools` first.

From the laptop, `ssh -p 8022 <phone-ip>`, any username, that password. Drop your public key into `~/.ssh/authorized_keys` on the phone after the first login and you're done with passwords. To land straight inside Fedora instead of Termux:

```sh
ssh -t -p 8022 <phone-ip> proot-distro login fedora
```

To get sshd back after a reboot, Termux:Boot runs everything in `~/.termux/boot/` once after the first unlock:

```sh
mkdir -p ~/.termux/boot
cat > ~/.termux/boot/sshd.sh <<'EOF'
#!/data/data/com.termux/files/usr/bin/sh
termux-wake-lock
sshd
EOF
chmod +x ~/.termux/boot/sshd.sh
```

`termux-wake-lock` stops the CPU sleeping while Termux is up. You get a permanent notification stuck in the tray for it, whatever.

## 5. One tap to Claude

Termux:Widget turns every executable in `~/.shortcuts` into a home screen button:

```sh
mkdir -p ~/.shortcuts
cat > ~/.shortcuts/Claude <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
exec proot-distro login fedora -- /root/.local/bin/claude
EOF
chmod +x ~/.shortcuts/Claude
```

Add the Termux:Widget widget to the home screen, tap Claude, and a terminal opens straight into Claude Code inside Fedora. Mine is a slightly bigger wrapper that fixes up PATH so the agent can see both Fedora's and Termux's binaries, but the three lines above are the whole idea.

## 6. Keeping it alive

This is the part that took months and still isn't perfect.

1. Battery set to Unrestricted for Termux and its add-ons, from step 1. Without it nothing survives the screen going off.
2. The phantom process killer. Android 12 and up kills any app with more than 32 child processes, and a proot Fedora with tmux and an agent in it gets there easily. This is the one step that needs a computer, and it sticks until a factory reset.

   On the phone: Settings, About phone, Software information, tap Build number seven times to get Developer options, then in Developer options turn on Wireless debugging and open it to get a pairing code.

   On the computer, with `adb` installed (it's in Android platform-tools, and most distros package it):
   ```sh
   adb pair <phone-ip>:<pairing-port>     # the code and both numbers are on the pairing screen
   adb connect <phone-ip>:<debug-port>    # the debug port is a different number, same screen
   adb shell "settings put global settings_enable_monitor_phantom_procs false"
   ```
   Wireless debugging turns itself off on every reboot, which is fine, because you only needed it for that one line. Don't build anything that depends on adb staying up.
4. sshd will still die every few days when Android's memory killer decides Termux is using too much. A scheduled job that restarts it if it isn't running is the fix. That's in [ai-layer.md](ai-layer.md).
5. Use tmux for anything long. A Termux session dies with the app. tmux inside the proot keeps going until something kills the whole tree.

## 7. Making it yours

Inside Fedora I use zsh with [starship](https://starship.rs), and the prompt is where the spirit name comes from:

```toml
# ~/.config/starship.toml
format = "[spirit ](bold #a07be0)$directory$git_branch$git_status$python$nodejs$cmd_duration$line_break$character"
[character]
success_symbol = "[❯](bold #f0b429)"
error_symbol   = "[❯](bold #e25822)"
```

`chsh -s "$(command -v zsh)"` works and it sticks, because `proot-distro login` reads the login shell out of the container's own `/etc/passwd`. Use the real path from `command -v`, not `/bin/zsh`, because Fedora puts zsh in `/usr/sbin` and chsh just errors out on a path that isn't there. It warns that the shell isn't in `/etc/shells` and changes it anyway. Older proot-distro ignored the passwd field entirely, which is why half the guides out there tell you to launch zsh from `.bashrc` instead.

Before you break something, back the container up. Give it an output file or it writes the tar to stdout, which on a 62 GB container means a binary dump into your terminal:

```sh
proot-distro backup fedora --output ~/fedora-backup.tar.xz
proot-distro restore ~/fedora-backup.tar.xz
```

Do that once you've got it how you like it.

## 8. Now give it a body

At this point you have a Linux box on your phone with an agent in it, and the agent still can't see or touch anything outside its own filesystem. That's the other half: [the-body](https://github.com/beqa-beridze/the-body) is an Android app that hands it the screen, the notifications and a way to ask you a question. Build it on this same phone, it takes about a minute, and its README picks up exactly where this page stops.

If you'd rather not, everything above still works on its own. You just have an agent that can think and use the network and nothing else.

## Getting rid of it

`proot-distro remove fedora` deletes the container and everything inside it, and there is no undo. Uninstall Termux and its add-ons the normal way. The one thing that does not clean itself up is the phantom process killer setting from step 6, which you can put back with `settings put global settings_enable_monitor_phantom_procs true` over adb.
