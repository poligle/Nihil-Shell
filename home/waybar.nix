# waybar.nix by poligle

{ config, pkgs, lib, ... }:
{
	programs.waybar = {
    		enable = true;
    		settings = {
      		mainBar = {
        		layer = "top";
        		position = "top";
        		mode = "dock";
        		height = 40;
        		exclusive = true;
        		passthrough = false;
        		margin-top = 5;
        		margin-left = 5;
        		margin-right = 5;
        		output = [ "eDP-1" "HDMI-A-1" ];
        		modules-left = [ "custom/applauncher" "hyprland/window" ];
        		modules-center = [ "hyprland/workspaces" ];
        		modules-right = [
          			"wireplumber"
          			"custom/microphone"
          			"backlight"
          			"cpu"
          			"memory"
          			"custom/network"
          			"custom/bluetooth"
          			"battery"
          			"clock"
          			"custom/lock"
          			"custom/power"
        		];

        		"custom/applauncher" = {
          			format = "󱄅 Apps";
          			tooltip = false;
          			on-click = "wofi --show drun";
        		};

        		"hyprland/window" = {
          			format = "{}";
          			rewrite = {
            				"(.*) — Mozilla Firefox" = "$1";
            				"(.*) - Mozilla Firefox" = "$1";
          			};
         	 		max-length = 40;
          			separate-outputs = true;
        		};

        		"hyprland/workspaces" = {
          			disable-scroll = false;
          			all-outputs = true;
          			format = "{icon}";
          			format-icons = {
            				default = "●";
          			};
          			persistent-workspaces = {
            				"*" = 3;
          			};
        		};

        		clock = {
          			tooltip = false;
          			interval = 60;
          			format = "{:%H:%M}";
          			format-alt = "{:%A %d %B}";
        		};

        		wireplumber = {
          			tooltip = false;
          			scroll-step = 5;
          			format = "{icon}  {volume}%";
          			format-muted = "󰝟 Muted";
          			format-icons = [ "" "" "" ];
          			on-click = "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle";
          			on-click-right = "pavucontrol";
        		};

        		"custom/microphone" = {
          			tooltip = false;
	  			exec = ''${pkgs.wireplumber}/bin/wpctl get-volume @DEFAULT_AUDIO_SOURCE@ | ${pkgs.gawk}/bin/awk '{ if ($0 ~ /MUTED/) print "󰍭  Muted"; else printf "󰍬 %d%%", int($2*100) }' '';
          			interval = 2;
          			signal = 1;
				return-type = "text";
          			on-click = "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle";
          			on-click-right = "pavucontrol";
        		};

        		backlight = {
          			tooltip = false;
          			device = "amdgpu_bl1";
          			format = "󰃠 {percent}%";
          			scroll-step = 5;
        		};

        		cpu = {
          			interval = 2;
          			format = "  {usage}%";
        		};

        		memory = {
          			interval = 2;
          			format = "  {}%";
          			format-alt = "  {used} GiB";
        		};

        		"custom/network" = {
          			exec = ''${pkgs.bash}/bin/bash -c 'if [ "$(${pkgs.networkmanager}/bin/nmcli -t -f WIFI g)" = "disabled" ]; then echo "󰖪 off"; else ssid=$(${pkgs.networkmanager}/bin/nmcli -t -f TYPE,STATE,CONNECTION dev status | grep "^wifi:connected:" | cut -d: -f3- | head -n1); if [ -n "$ssid" ] && [ "$ssid" != "--" ]; then echo "󱚽 $ssid"; else echo "󰖩 on"; fi; fi' '';
          			interval = 3;
          			tooltip = false;
          			return-type = "text";
         	 		on-click = ''${pkgs.bash}/bin/bash -c 'if [ "$(${pkgs.networkmanager}/bin/nmcli -t -f WIFI g)" = "enabled" ]; then ${pkgs.networkmanager}/bin/nmcli radio wifi off; else ${pkgs.networkmanager}/bin/nmcli radio wifi on; fi' '';
          			on-click-right = "nm-connection-editor";
        		};

        		"custom/bluetooth" = {
	  			exec = ''${pkgs.bash}/bin/bash -c 'if ${pkgs.util-linux}/bin/rfkill list bluetooth | grep -q "Soft blocked: yes"; then echo "󰂲 off"; else dev=$(${pkgs.bluez}/bin/bluetoothctl devices Connected | cut -d" " -f3- | head -n1); if [ -n "$dev" ]; then echo "󰂱 $dev"; else echo " on"; fi; fi' '';
          			interval = 3;
          			tooltip = false;
          			return-type = "text";
          			on-click = ''${pkgs.bash}/bin/bash -c 'if ${pkgs.util-linux}/bin/rfkill list bluetooth | grep -q "Soft blocked: yes"; then ${pkgs.util-linux}/bin/rfkill unblock bluetooth; else ${pkgs.util-linux}/bin/rfkill block bluetooth; fi' '';
          			on-click-right = "blueman-manager";
        		};

        		battery = {
          			tooltip = false;
          			interval = 10;
          			format = "{icon} {capacity}%";
          			format-alt = "{time}";
          			format-icons = [ "󰂃" "󰁺" "󰁻" "󰁼" "󰁽" "󰁾" "󰁿" "󰂀" "󰂁" "󰂂" "󰁹" ];
        		};

        		"custom/lock" = {
          			format = "";
          			tooltip = false;
          			on-click = "hyprlock";
        		};

        		"custom/power" = {
          			format = "";
          			tooltip = false;
          			on-click = "systemctl poweroff";
        		};
      		};
    	};
    	style = ''
      	@define-color text      #ffffff;
      	@define-color surface0  #2c2c2c;
      	@define-color surface1  #837d9b;
      	@define-color color1    #e8e8ff;
      	@define-color color2    #bebeef;
      	@define-color color3    #cf4e4e;
      	@define-color color4    #87d33a;
      	@define-color color5    #fffc82;
      	@define-color color6    #6bafc4;

      	* {
        	border: none;
        	border-radius: 0;
        	font-family: JetBrainsMono Nerd Font;
        	font-weight: bold;
        	font-size: 14px;
        	min-height: 0;
      	}
      	window#waybar {
        	background: alpha(@surface0, 0.6);
        	color: @text;
        	border-radius: 10px;
      	}
      	#custom-applauncher,
      	#workspaces,
      	#clock,
      	#wireplumber,
      	#custom-microphone,
      	#backlight,
      	#cpu,
      	#memory,
      	#custom-network,
      	#custom-bluetooth,
      	#battery,
      	#custom-lock,
      	#custom-power,
      	#window {
      		background-color: alpha(@surface0, 0.6);
        	padding: 0.22rem 0.4rem;
        	margin-top: 5px;
        	margin-bottom: 5px;
        	margin-left: 0;
        	margin-right: 0;
        	box-shadow: none;
        	border: none;
      	}
	#custom-applauncher {
        	color: @color1;
        	border-radius: 0.5rem;
        	margin-left: 0.4rem;
        	margin-right: 2rem;
        	padding: 0.38rem 0.7rem;
      	}
      	#window {
        	color: @text;
        	background: transparent;
        	padding: 0.3rem 0.4rem;
      	}
      	#workspaces {
        	border-radius: 0.5rem;
        	margin-left: 1rem;
        	padding: 0 0.35rem;
      	}
      	#workspaces button {
        	color: @surface1;
        	border-radius: 0.7rem;
        	padding: 0 0.35rem;
        	margin: 0;
      	}
      	#workspaces button label {
          	font-size: 22px;
      	}
      	#workspaces button.active {
        	color: @color1;
      	}
      	#workspaces button:hover {
        	color: @color2;
      	}
      	#clock {
        	color: @color1;
        	border-radius: 0.7rem;
        	padding: 0.38rem 0.8rem;
        	margin-right: 1rem;
      	}
      	#wireplumber {
        	color: @color1;
        	border-radius: 0.5rem 0 0 0.5rem;
        	padding-left: 1rem;
        	padding-right: 0.45rem;
      	}
      	#custom-microphone {
        	color: @color1;
        	border-radius: 0;
        	padding-left: 0.45rem;
        	padding-right: 0.45rem;
      	}
      	#backlight {
        	color: @color1;
        	border-radius: 0 0.5rem 0.5rem 0;
        	padding-left: 0.45rem;
        	padding-right: 1rem;
        	margin-right: 1rem;
      	}
      	#cpu {
        	color: @color1;
        	border-radius: 0.5rem 0 0 0.5rem;
        	padding-left: 1rem;
        	padding-right: 0.45rem;
      	}
      	#memory {
        	color: @color1;
        	border-radius: 0 0.5rem 0.5rem 0;
        	padding-left: 0.45rem;
        	padding-right: 1rem;
        	margin-right: 1rem;
      	}
      	#custom-network {
        	color: @color1;
        	border-radius: 0.5rem 0 0 0.5rem;
        	padding-left: 1rem;
        	padding-right: 0.6rem;
      	}
      	#custom-bluetooth {
        	color: @color1;
        	border-radius: 0;
        	padding-left: 0.35rem;
        	padding-right: 0.6rem;
      	}
      	#battery {
        	color: @color1;
        	border-radius: 0 0.5rem 0.5rem 0;
        	padding-left: 0.6rem;
        	padding-right: 1rem;
        	margin-right: 1rem;
      	}
      	#battery.charging {
        	color: @color4;
      	}
      	#battery.warning:not(.charging) {
        	color: @color3;
      	}
      	#custom-lock {
        	color: @color6;
        	border-radius: 0.5rem 0 0 0.5rem;
        	padding-left: 1rem;
        	padding-right: 0.45rem;
      	}
      	#custom-power {
        	color: @color3;
        	border-radius: 0 0.5rem 0.5rem 0;
        	padding-left: 0.45rem;
        	padding-right: 1rem;
        	margin-right: 0.4rem;
      	}
    '';
  };
}

