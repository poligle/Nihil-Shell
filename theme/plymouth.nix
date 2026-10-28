# plymouth.nix by poligle
#
# NIHIL boot splash: the NixOS snowflake as an LED matrix that switches on
# from the centre, then a band of light sweeps it while the system boots.
# Frames are rendered at build time (theme/plymouth.py). The prompt, question
# and message handlers are the ones from Stylix's Plymouth theme.

{ pkgs }:
let
  python = pkgs.python3.withPackages (ps: [ ps.pillow ]);

  # Plymouth colours are 0-1 floats.
  ink = "0.949, 0.949, 0.949";
  intro = 36;
  loop = 60;

  script = pkgs.writeText "nihil.script" ''
    center_x = Window.GetWidth() / 2;
    center_y = Window.GetHeight() / 2;
    baseline_y = Window.GetHeight() * 0.9;
    message_y = Window.GetHeight() * 0.75;

    ### BACKGROUND ###

    Window.SetBackgroundTopColor(0, 0, 0);
    Window.SetBackgroundBottomColor(0, 0, 0);

    ### LOGO ###

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

    fun refresh_callback () {
      if (logo.animated) {
        step = Math.Int(logo.tick / 2);
        if (step < ${toString intro}) {
          frame_index = step;
        } else {
          frame_index = ${toString intro} + ((step - ${toString intro}) % ${toString loop});
        }
        logo.sprite.SetImage(logo.frames[frame_index]);
        logo.tick++;
      }
    }

    fun stop_animation () {
      logo.animated = 0;
      logo.sprite.SetImage(logo.static);
    }

    fun start_animation () {
      logo.animated = 1;
    }

    Plymouth.SetRefreshFunction(refresh_callback);

    ### PASSWORD ###

    prompt = null;
    bullets = null;
    bullet.image = Image.Text("•", ${ink});

    fun password_callback (prompt_text, bullet_count) {
      stop_animation();

      prompt.image = Image.Text(prompt_text, ${ink});
      prompt.sprite = Sprite(prompt.image);
      prompt.sprite.SetPosition(
        center_x - (prompt.image.GetWidth() / 2),
        baseline_y - prompt.image.GetHeight(),
        1
      );

      total_width = bullet_count * bullet.image.GetWidth();
      start_x = center_x - (total_width / 2);

      bullets = null;
      for (i = 0; i < bullet_count; i++) {
        bullets[i].sprite = Sprite(bullet.image);
        bullets[i].sprite.SetPosition(
          start_x + (i * bullet.image.GetWidth()),
          baseline_y + bullet.image.GetHeight(),
          1
        );
      }
    }

    Plymouth.SetDisplayPasswordFunction(password_callback);

    ### QUESTION ###

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

    ### MESSAGE ###

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

    ### NORMAL ###

    fun normal_callback () {
      prompt = null;
      bullets = null;

      question = null;
      answer = null;

      message = null;

      start_animation();
    }

    Plymouth.SetDisplayNormalFunction(normal_callback);

    ### QUIT ###

    fun quit_callback () {
      prompt = null;
      bullets = null;
      stop_animation();
    }

    Plymouth.SetQuitFunction(quit_callback);
  '';
in
pkgs.runCommand "nihil-plymouth" { nativeBuildInputs = [ python ]; } ''
  dir="$out/share/plymouth/themes/nihil"
  mkdir -p "$dir"
  python3 ${./plymouth.py} ${./art/snowflake-29.txt} "$dir"
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
