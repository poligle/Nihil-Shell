# What's in it

- **Frame and bar.** One black shape around every screen. Its left side widens into the
  bar: NixOS mark, workspaces as LEDs, the active app, tray, status, a 10-LED battery
  gauge, the clock in dots and a red privacy LED while something records the mic.
- **Drawers.** The dashboard, the settings panel and the launcher are bumps of the frame
  itself, with concave joints, so they look like part of the hardware.
- **Dashboard.** Time, music with the cover rendered as a dot matrix and a spectrum in
  LED columns, CPU/RAM/temperature dials, a network oscilloscope, a kanban (to do, doing,
  done: drag a card where it goes, its pencil writes it again, a broom clears the done ones),
  and Vector, a box in LEDs: paste or drop on it a text, a picture, a video or any file and
  it shrinks away to the phone; what the phone sends waits there, to copy, save or open.
- **Settings.** Circular toggles (caffeine among them, which keeps the screen from dimming,
  locking or sleeping; the night light, with its intensity), segmented sliders, Wi-Fi (with
  passwords and WPA-Enterprise hand-off), Bluetooth, as it was when the computer shut down,
  audio output, notification history, session.
- **Preferences.** Your name and password, language, keyboard and time zone, wallpaper
  and desktop widgets, the screens, shortcuts and programs, the computer's name, Nilo,
  the clipboard history, the boot sound, fingerprint and SSH, in one sheet (`SUPER + O`) that the first login opens as a welcome. The wallpaper,
  the widgets and the password change at once; the rest waits until applied, and applying
  rebuilds the system in the background.
- **Generations, from Preferences.** Every rebuild is a whole system NixOS keeps. Each one
  says when it was made, its NixOS, kernel and NIHIL, and which packages it changed;
  one click goes back to it, now and at boot, or boots it just once. How long they stay,
  and cleaning now, with what it frees.
- **The phone as a deck.** With [NIHIL Launcher](https://github.com/poligle/Nihil-Launcher) on Android, paired with a QR
  from Preferences, the phone opens the computer's apps and web pages, plays and skips
  its music, turns its volume, locks it and is its trackpad, with this desktop's gestures;
  the dashboard's kanban stays in sync with it, and Vector carries things either way.
  Over HTTPS pinned to this computer. See
  [The phone as a deck](phone.md).
- **An installer.** An ISO that installs NIHIL on a whole disk, or next to Windows or
  another Linux in room it makes by shrinking it safely. See [Install](install.md).
- **Launcher.** Monochrome app grid that regains colour on the selection, `>` for
  actions, `=` for a calculator, `?` for Nilo.
- **Copy, paste and the clipboard history.** One modifier for both, as on a Mac: `SUPER + C`
  copies and `SUPER + V` pastes, in kitty too. Held a moment longer, `SUPER + V`
  brings out the last copies, text and pictures, from the top of the frame: `V` again goes
  to the next one, and letting go of `SUPER` pastes it where you were (`Esc`: none). The
  window keeps the keyboard all along, so what was open in it stays open. The one chosen
  is lit, its picture in colour. What a password manager copies is never kept.
- **Nilo.** An optional assistant with a local model (Qwen 3.5 on Ollama): two white eyes
  that wake up while you type. Three levels of what it may do: talk (and search the web if
  you let it); work in a repository of yours, its files, git and the terminal, each step
  confirmed; or use the whole desktop as you would: see what is open and the screen, type
  in Writer, put on a song, open Zen on a video, move windows, turn the volume, send things
  to the phone, asking only before what carries a risk. Close the launcher mid-answer and it
  tells you when it's done, from the bar. See [Nilo](nilo.md).
- **Light on the edge.** In the spirit of Nothing's Glyph Interface, every notification
  sends a segment of light around the frame; critical ones run twice, in red, like the
  battery warnings at 15, 10 and 5 %. Plugging in the charger sends two lights up both
  sides from the bottom, which meet at the top, like the launcher on the phone. Work
  that takes a while stays on it: a rebuild (Preferences, updating, a generation) keeps
  the two lights as far up as it has got and rises when it is done; a download in Zen,
  Firefox or Chromium sends a faint stretch round until it ends. Anything else can use
  it too: `nihil-ipc glyph progress <id> <0..1>`, then `done <id>`.
- **Wallpapers as LED matrices.** Every picture in `wallpapers/`, and in a machine's
  `/etc/nixos/wallpapers` (PNG, JPEG, GIF or WebP, with any name), is rendered at build
  time as dots, once per output at its native size, so each dot lands on exact pixels. A
  GIF moves on the desktop. Each picture on each screen is drawn once and kept: a rebuild
  only draws the new ones. The [studio](https://nihilshell.com/studio/) does the same in
  the browser with any picture, moving ones too (`docs/studio/`, the same numbers as
  `theme/dotmatrix.py`).
- **Boot, login, lock.** The NixOS snowflake switching on LED by LED (Plymouth, played
  whole at least once on the way up and on the way down) with the power-off notes going
  up, unless the session was left muted, a greeter with the lock screen's face (its
  own, in Quickshell: the time in dots, the password as dots, a finger or the password) and
  a lock screen with what is playing in a corner, on a panel of its own: the cover in dots,
  the progress in LEDs and buttons you can click (hyprlock).
- **Pictures, videos and PDFs.** imv, mpv and Zathura open them, from Thunar or from
  Vector, in the same black and greys, and stay out of the launcher. A picture opens with
  the rest of its folder an arrow away; mpv plays music files too.
- **fastfetch in dots.** The same snowflake, drawn with `●` and `·`, monochrome keys in
  NIHIL's own greys and the palette as a row of LEDs.
- **Spanish or English.** One option switches every string of the shell, the lock screen,
  the greeter and the scripts, and the language of their dates.
- **Its own sound.** A set of short digital blips, synthesised for NIHIL; the previous
  sounds are one option away.
