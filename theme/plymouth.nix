# plymouth.nix by poligle

# passphrase: what the disk's password is called, in the system's language (theme/i18n.nix). It's
# shown instead of what asks for it: systemd-cryptsetup's words are English, whatever the language.
# failed: what a password that didn't open the disk is said as, with $ATTEMPTS for how many times.
{ pkgs, waitForSound ? false, passphrase ? "Disk passphrase", failed ? "Failed ($ATTEMPTS)" }:
let
  python = pkgs.python3.withPackages (ps: [ ps.pillow ]);
  t = import ./nihil.nix;

  # A colour as the script takes it: red, green and blue, from 0 to 1.
  rgb = hex: builtins.concatStringsSep ", "
    (map (i: toString (pkgs.lib.fromHexString (builtins.substring i 2 hex) / 255.0)) [ 0 2 4 ]);
  ink = rgb t.palette.ink;
  muted = rgb t.palette.muted;

  # Space Mono, the one font the initrd has (modules/plymouth.nix), at the login screen's sizes:
  # 13 px for what the field asks, 12 for what went wrong.
  asks = "Space Mono 9.75";
  says = "Space Mono 9";

  # The words around the count, for the script to put it in between.
  around = builtins.filter builtins.isString (builtins.split "\\$ATTEMPTS" failed);
  failure = if builtins.length around > 1
    then "${builtins.toJSON (builtins.head around)} + failures + ${builtins.toJSON (builtins.elemAt around 1)}"
    else builtins.toJSON failed;

  intro = 36;
  loop = 60;

  script = pkgs.writeText "nihil.script" ''
    baseline_y = 0;

    fun layout () {
      screen = 0;
      shortest = 0;
      while (Window.GetWidth(screen)) {
        Window.SetX(screen, Math.Int(0 - Window.GetWidth(screen) / 2));
        Window.SetY(screen, Math.Int(0 - Window.GetHeight(screen) / 2));
        if (shortest == 0) {
          shortest = Window.GetHeight(screen);
        }
        if (Window.GetHeight(screen) < shortest) {
          shortest = Window.GetHeight(screen);
        }
        screen++;
      }
      baseline_y = shortest * 0.4;
    }

    layout();
    center_x = 0;
    center_y = 0;

    Window.SetBackgroundTopColor(0, 0, 0);
    Window.SetBackgroundBottomColor(0, 0, 0);

    logo.static = Image("logo.png");
    for (i = 0; i < ${toString (intro + loop)}; i++) {
      logo.frames[i] = Image("frame-" + i + ".png");
    }

    logo.sprite = Sprite(logo.frames[0]);
    logo.sprite.SetPosition(
      center_x - (logo.static.GetWidth() / 2),
      center_y - (logo.static.GetHeight() / 2),
      1
    );

    logo.animated = 1;
    logo.tick = 0;

    logo.opened = 1;
    if (${if waitForSound then "1" else "0"}) {
      if (Plymouth.GetMode() == "boot") {
        logo.opened = 0;
      }
    }
    logo.waited = 0;

    fun open_logo () {
      if (logo.opened == 0) {
        logo.opened = 1;
        logo.tick = 0;
      }
    }

    fun status_callback (status) {
      if (status == "nihil-open") {
        open_logo();
      }
    }

    Plymouth.SetUpdateStatusFunction(status_callback);

    fun refresh_callback () {
      layout();
      if (logo.animated) {
        if (logo.opened == 0) {
          logo.waited++;
          if (logo.waited > 500) {
            open_logo();
          }
        }
        if (logo.opened) {
          step = Math.Int(logo.tick / 2);
          if (step < ${toString intro}) {
            frame_index = step;
          } else {
            frame_index = ${toString intro} + ((step - ${toString intro}) % ${toString loop});
          }
          logo.sprite.SetImage(logo.frames[frame_index]);
          logo.tick++;
        } else {
          logo.sprite.SetImage(logo.frames[0]);
        }
      }
    }

    fun stop_animation () {
      logo.animated = 0;
      if (logo.opened) {
        logo.sprite.SetImage(logo.static);
      } else {
        logo.sprite.SetImage(logo.frames[0]);
      }
    }

    fun start_animation () {
      logo.animated = 1;
    }

    Plymouth.SetRefreshFunction(refresh_callback);

    prompt = null;
    bullets = null;
    field = null;
    note = null;
    field_image = Image("field.png");
    field_wrong = Image("field-wrong.png");
    dot_image = Image("dot.png");
    led_image = Image("led.png");

    # The field as far below the logo's middle as the login screen's is below its clock's, and
    # what went wrong 54 under it, as there.
    field_y = 226;
    note_y = field_y + 54;
    message_y = note_y + 40;

    # Asked again for the same disk once answered: the password didn't open it.
    asking = 0;
    asked = "";
    failures = 0;

    fun password_callback (prompt_text, bullet_count) {
      stop_animation();

      if (asking == 0) {
        if (prompt_text == asked) {
          failures++;
        } else {
          failures = 0;
        }
        asked = prompt_text;
        asking = 1;
      }
      # Wrong until something is typed again, as on the login screen.
      wrong = 0;
      if (failures > 0 && bullet_count == 0) {
        wrong = 1;
      }

      if (wrong) {
        field.sprite = Sprite(field_wrong);
      } else {
        field.sprite = Sprite(field_image);
      }
      field.sprite.SetPosition(
        Math.Int(center_x - field_image.GetWidth() / 2),
        Math.Int(field_y - field_image.GetHeight() / 2),
        1
      );

      prompt = null;
      bullets = null;
      if (bullet_count == 0) {
        prompt.image = Image.Text(${builtins.toJSON passphrase}, ${muted}, 1, ${builtins.toJSON asks});
        prompt.sprite = Sprite(prompt.image);
        prompt.sprite.SetPosition(
          Math.Int(center_x - prompt.image.GetWidth() / 2),
          Math.Int(field_y - prompt.image.GetHeight() / 2),
          2
        );
      } else {
        shown = bullet_count;
        if (shown > 15) {
          shown = 15;
        }
        start_x = Math.Int(center_x - (shown * 17 - 7) / 2);
        for (i = 0; i < shown; i++) {
          bullets[i].sprite = Sprite(dot_image);
          bullets[i].sprite.SetPosition(start_x + i * 17, Math.Int(field_y - dot_image.GetHeight() / 2), 2);
        }
      }

      note = null;
      if (failures > 0) {
        if (wrong) {
          note.image = Image.Text(${failure}, ${ink}, 1, ${builtins.toJSON says});
        } else {
          note.image = Image.Text(${failure}, ${muted}, 1, ${builtins.toJSON says});
        }
        # With the LED, 6 px and 8 from the words, while it's wrong.
        width = note.image.GetWidth();
        if (wrong) {
          width = width + 14;
          note.led = Sprite(led_image);
          note.led.SetPosition(
            Math.Int(center_x - width / 2),
            Math.Int(note_y - led_image.GetHeight() / 2),
            2
          );
        }
        note.sprite = Sprite(note.image);
        note.sprite.SetPosition(
          Math.Int(center_x + width / 2 - note.image.GetWidth()),
          Math.Int(note_y - note.image.GetHeight() / 2),
          2
        );
      }
    }

    Plymouth.SetDisplayPasswordFunction(password_callback);

    question = null;
    answer = null;

    fun question_callback (prompt_text, entry) {
      stop_animation();

      question = null;
      answer = null;

      question.image = Image.Text(prompt_text, ${ink});
      question.sprite = Sprite(question.image);
      question.sprite.SetPosition(
        center_x - (question.image.GetWidth() / 2),
        baseline_y - question.image.GetHeight(),
        1
      );

      answer.image = Image.Text(entry, ${ink});
      answer.sprite = Sprite(answer.image);
      answer.sprite.SetPosition(
        center_x - (answer.image.GetWidth() / 2),
        baseline_y + answer.image.GetHeight(),
        1
      );
    }

    Plymouth.SetDisplayQuestionFunction(question_callback);

    message = null;

    fun message_callback (text) {
      message.image = Image.Text(text, ${ink});
      message.sprite = Sprite(message.image);
      message.sprite.SetPosition(
        center_x - message.image.GetWidth() / 2,
        message_y,
        1
      );
    }

    Plymouth.SetMessageFunction(message_callback);

    fun normal_callback () {
      prompt = null;
      bullets = null;
      field = null;
      note = null;
      asking = 0;

      question = null;
      answer = null;

      message = null;

      start_animation();
    }

    Plymouth.SetDisplayNormalFunction(normal_callback);

    fun quit_callback () {
      prompt = null;
      bullets = null;
      field = null;
      note = null;
      stop_animation();
    }

    Plymouth.SetQuitFunction(quit_callback);
  '';
in
pkgs.runCommand "nihil-plymouth" { nativeBuildInputs = [ python ]; } ''
  dir="$out/share/plymouth/themes/nihil"
  mkdir -p "$dir"
  python3 ${./plymouth.py} ${./art/snowflake-29.txt} "$dir" --colours ${t.palette.void} ${t.palette.line} ${t.palette.signal} ${t.palette.ink}
  cp ${script} "$dir/nihil.script"
  {
    printf '[Plymouth Theme]\n'
    printf 'Name=NIHIL\n'
    printf 'Description=ex nihilo\n'
    printf 'ModuleName=script\n\n'
    printf '[script]\n'
    printf 'ImageDir=%s\n' "$dir"
    printf 'ScriptFile=%s\n' "$dir/nihil.script"
  } > "$dir/nihil.plymouth"
''
