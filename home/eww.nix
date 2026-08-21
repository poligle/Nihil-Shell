# eww.nix by poligle

{ config, pkgs, lib, ... }:

let
  palette           = config.lib.stylix.colors.withHashtag;
  paletteRgb        = config.lib.stylix.colors;
  fontMonospace     = config.stylix.fonts.monospace.name;
  fontSansSerif     = config.stylix.fonts.sansSerif.name;
  fontClockDisplay  = "Poppins";
  widgetOpacity     = "0.3";
  ewwNetworkMonitor = pkgs.writeShellScriptBin "eww-network-monitor" 
  ''
    export PATH="${lib.makeBinPath [ pkgs.iproute2 pkgs.gawk pkgs.coreutils ]}:$PATH"  
    readonly SAMPLING_INTERVAL_SECONDS=1

    format_bytes_human() {
      awk -v bytes="$1" 'BEGIN {
        if      (bytes >= 1048576) printf "%.1f MB/s", bytes / 1048576;
        else if (bytes >= 1024)    printf "%.0f KB/s", bytes / 1024;
        else                       printf "%.0f B/s",  bytes;
      }'
    }

    while true; do
      network_interface=$(ip route 2>/dev/null | awk '/^default/ {print $5; exit}')

      if [ -z "$network_interface" ] || [ ! -r "/sys/class/net/$network_interface/statistics/rx_bytes" ]; then
        printf '{"interface":"offline","rx_rate_bps":0,"tx_rate_bps":0,"rx_rate_kbps":0,"tx_rate_kbps":0,"rx_formatted":"—","tx_formatted":"—"}\n'
        sleep "$SAMPLING_INTERVAL_SECONDS"
        continue
      fi

      rx_bytes_initial=$(cat "/sys/class/net/$network_interface/statistics/rx_bytes")
      tx_bytes_initial=$(cat "/sys/class/net/$network_interface/statistics/tx_bytes")
      
      sleep "$SAMPLING_INTERVAL_SECONDS"
      
      rx_bytes_final=$(cat "/sys/class/net/$network_interface/statistics/rx_bytes")
      tx_bytes_final=$(cat "/sys/class/net/$network_interface/statistics/tx_bytes")

      rx_rate_bps=$(( (rx_bytes_final - rx_bytes_initial) / SAMPLING_INTERVAL_SECONDS ))
      tx_rate_bps=$(( (tx_bytes_final - tx_bytes_initial) / SAMPLING_INTERVAL_SECONDS ))

      [ "$rx_rate_bps" -lt 0 ] && rx_rate_bps=0
      [ "$tx_rate_bps" -lt 0 ] && tx_rate_bps=0

      rx_rate_kbps=$(awk -v bytes="$rx_rate_bps" 'BEGIN {printf "%.2f", bytes / 1024}')
      tx_rate_kbps=$(awk -v bytes="$tx_rate_bps" 'BEGIN {printf "%.2f", bytes / 1024}')

      rx_formatted=$(format_bytes_human "$rx_rate_bps")
      tx_formatted=$(format_bytes_human "$tx_rate_bps")

      printf '{"interface":"%s","rx_rate_bps":%s,"tx_rate_bps":%s,"rx_rate_kbps":%s,"tx_rate_kbps":%s,"rx_formatted":"%s","tx_formatted":"%s"}\n' \
        "$network_interface" \
        "$rx_rate_bps" \
        "$tx_rate_bps" \
        "$rx_rate_kbps" \
        "$tx_rate_kbps" \
        "$rx_formatted" \
        "$tx_formatted"
    done
  '';

  ewwMediaMonitor = pkgs.writeShellScriptBin "eww-media-monitor"
  ''
    export PATH="${lib.makeBinPath [ pkgs.playerctl pkgs.curl pkgs.gawk pkgs.gnused pkgs.coreutils ]}:$PATH"

    readonly ARTWORK_CACHE_DIRECTORY="/tmp/eww-media-artwork"
    readonly FIELD_DELIMITER="|||"

    mkdir -p "$ARTWORK_CACHE_DIRECTORY"

    escape_json_string() {
      printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
    }

    extract_field() {
      printf '%s' "$2" | awk -F'\\|\\|\\|' -v index_number="$1" '{print $index_number}'
    }

    resolve_artwork_path() {
      artwork_url="$1"

      case "$artwork_url" in
        file://*)
          printf '%s' "$artwork_url" | sed 's|^file://||'
          ;;
        http://*|https://*)
          cache_key=$(printf '%s' "$artwork_url" | md5sum | awk '{print $1}')
          cache_file="$ARTWORK_CACHE_DIRECTORY/$cache_key"
          if [ ! -s "$cache_file" ]; then
            curl --silent --fail --location --max-time 5 --output "$cache_file" "$artwork_url" || rm -f "$cache_file"
          fi
          [ -s "$cache_file" ] && printf '%s' "$cache_file"
          ;;
        *)
          printf "%s" ""
          ;;
      esac
    }

    emit_idle_state() {
      printf '{"active":false,"player":"","status":"Stopped","artist":"","title":"Nada reproduciéndose","artwork":""}\n'
    }

    emit_idle_state

    playerctl --follow --format "{{playerName}}$FIELD_DELIMITER{{status}}$FIELD_DELIMITER{{artist}}$FIELD_DELIMITER{{title}}$FIELD_DELIMITER{{mpris:artUrl}}" metadata 2>/dev/null |
    while IFS= read -r raw_line; do
      if [ -z "$raw_line" ]; then
        emit_idle_state
        continue
      fi

      player_name=$(extract_field 1 "$raw_line")
      playback_status=$(extract_field 2 "$raw_line")
      track_artist=$(extract_field 3 "$raw_line")
      track_title=$(extract_field 4 "$raw_line")
      artwork_url=$(extract_field 5 "$raw_line")

      artwork_path=$(resolve_artwork_path "$artwork_url")

      printf '{"active":true,"player":"%s","status":"%s","artist":"%s","title":"%s","artwork":"%s"}\n' \
        "$(escape_json_string "$player_name")" \
        "$(escape_json_string "$playback_status")" \
        "$(escape_json_string "$track_artist")" \
        "$(escape_json_string "$track_title")" \
        "$(escape_json_string "$artwork_path")"
    done
  '';

  ewwMediaPosition = pkgs.writeShellScriptBin "eww-media-position"
  ''
    export PATH="${lib.makeBinPath [ pkgs.playerctl pkgs.gawk pkgs.coreutils ]}:$PATH"

    position_seconds=$(playerctl position 2>/dev/null)
    length_microseconds=$(playerctl metadata mpris:length 2>/dev/null)

    if [ -z "$position_seconds" ] || [ -z "$length_microseconds" ]; then
      printf '{"elapsed":"0:00","total":"0:00","fraction":0}\n'
      exit 0
    fi

    awk -v position="$position_seconds" -v length_us="$length_microseconds" 'BEGIN {
      total_seconds = length_us / 1000000;

      elapsed_minutes = int(position / 60);
      elapsed_seconds = int(position % 60);
      total_minutes   = int(total_seconds / 60);
      total_remainder = int(total_seconds % 60);

      fraction = (total_seconds > 0) ? (position / total_seconds) * 100 : 0;
      if (fraction > 100) fraction = 100;

      printf "{\"elapsed\":\"%d:%02d\",\"total\":\"%d:%02d\",\"fraction\":%.1f}\n",
        elapsed_minutes, elapsed_seconds, total_minutes, total_remainder, fraction;
    }'
  '';

in
{
  home.packages = 
  [
    pkgs.eww
    pkgs.poppins
    pkgs.playerctl
    ewwNetworkMonitor
    ewwMediaMonitor
    ewwMediaPosition
  ];

  xdg.configFile."eww/eww.yuck".text = 
  ''
    (defpoll clockHours   :interval "5s"  `date +'%H'`)
    (defpoll clockMinutes :interval "5s"  `date +'%M'`)
    (defpoll clockWeekday :interval "60s" `date +'%A' | awk '{print toupper($0)}'`)
    (defpoll clockDate    :interval "60s" `date +'%d de %B'`)

    (deflisten networkTelemetry
    :initial '{"interface":"...","rx_rate_bps":0,"tx_rate_bps":0,"rx_rate_kbps":0,"tx_rate_kbps":0,"rx_formatted":"—","tx_formatted":"—"}'
    "eww-network-monitor")

    (deflisten mediaTelemetry
    :initial '{"active":false,"player":"","status":"Stopped","artist":"","title":"Nada reproduciéndose","artwork":""}'
    "eww-media-monitor")

    (defpoll mediaPosition :interval "1s"
    :initial '{"elapsed":"0:00","total":"0:00","fraction":0}'
    `eww-media-position`)

    (defwidget clock-widget []
    (box :class "widget-container clock-container" 
    :orientation "v" 
    :space-evenly false
    :vexpand true
    :hexpand true
    :valign "fill"
    :halign "fill"
    (box :class "clock-content"
    :orientation "v"
    :space-evenly false
    :vexpand true
    :valign "center"
    :halign "center"
    (box :class "clock-time-row"
    :orientation "h"
    :space-evenly false
    :halign "center"
    (label :class "clock-label-hours"     :text clockHours)
    (label :class "clock-label-separator" :text ":")
    (label :class "clock-label-minutes"   :text clockMinutes))
    (label :class "clock-label-weekday" :text clockWeekday :halign "center")
    (label :class "clock-label-date"    :text clockDate    :halign "center"))))

    (defwindow window-clock
    :monitor 0
    :geometry (geometry :x "40px" :y "40px"
    :width "300px" :height "250px"
    :anchor "top left")
    :stacking "bg"
    :exclusive false
    :focusable "none"
    (clock-widget))

    (defwidget network-widget []
    (box :class "widget-container network-container" 
    :orientation "v" 
    :space-evenly false 
    :vexpand true
    :hexpand true
    :valign "fill"
    :halign "fill"
    :spacing 2
    (box :class "network-header"
    :orientation "h" 
    :space-evenly false 
    :hexpand true
    (label :class "network-interface-id" :text {networkTelemetry.interface})
    (box :hexpand true)
    (label :class "network-metric-rx" :text "↓ ''${networkTelemetry.rx_formatted}")
    (label :class "network-metric-tx" :text "↑ ''${networkTelemetry.tx_formatted}"))
    (graph :class "network-throughput-graph"
    :value {networkTelemetry.rx_rate_kbps}
    :thickness 2
    :time-range "60s"
    :min 0
    :dynamic true
    :hexpand true
    :height 38)))

    (defwindow window-network
    :monitor 0
    :geometry (geometry :x "40px" :y "308px"
    :width "300px" :height "96px"
    :anchor "top left")
    :stacking "bg"
    :exclusive false
    :focusable "none"
    (network-widget))

    (defwidget media-widget []
    (box :class "widget-container media-container"
    :orientation "h"
    :space-evenly false
    :vexpand true
    :hexpand true
    :valign "fill"
    :halign "fill"
    :spacing 12
    (box :class "media-artwork-frame"
    :valign "center"
    :halign "start"
    (image :class "media-artwork-image"
    :path {mediaTelemetry.artwork}
    :image-width 60
    :image-height 60
    :visible {mediaTelemetry.artwork != ""})
    (label :class "media-artwork-placeholder"
    :text "♪"
    :visible {mediaTelemetry.artwork == ""}))
    (box :class "media-details"
    :orientation "v"
    :space-evenly false
    :vexpand true
    :hexpand true
    :valign "center"
    :spacing 3
    (label :class "media-player-name"
    :text {mediaTelemetry.player}
    :halign "start"
    :visible {mediaTelemetry.active})
    (label :class "media-track-title"
    :text {mediaTelemetry.title}
    :halign "start"
    :limit-width 18
    :truncate true)
    (scale :class "media-progress-bar"
    :value {mediaPosition.fraction}
    :min 0
    :max 100
    :active false
    :hexpand true)
    (box :class "media-controls-row"
    :orientation "h"
    :space-evenly false
    :hexpand true
    (label :class "media-time-elapsed"
    :text "''${mediaPosition.elapsed} / ''${mediaPosition.total}")
    (box :hexpand true)
    (button :class "media-control-button"
    :onclick "playerctl previous"
    "󰒮")
    (button :class "media-control-button"
    :onclick "playerctl play-pause"
    {mediaTelemetry.status == "Playing" ? "󰏤" : "󰐊"})
    (button :class "media-control-button"
    :onclick "playerctl next"
    "󰒭")))))

    (defwindow window-media
    :monitor 0
    :geometry (geometry :x "40px" :y "422px"
    :width "300px" :height "108px"
    :anchor "top left")
    :stacking "bg"
    :exclusive false
    :focusable "none"
    (media-widget))
  '';

  xdg.configFile."eww/eww.scss".text = 
  ''
    * { 
      all: unset; 
    }

    .widget-container 
    {
      background-color: rgba(${paletteRgb.base01-dec-r}, ${paletteRgb.base01-dec-g}, ${paletteRgb.base01-dec-b}, ${widgetOpacity});
      color: ${palette.base05};
      border-radius: 20px;
      font-family: "${fontSansSerif}";
      min-width: 300px;
    }

    .clock-container 
    {
      padding: 22px 24px;
    }

    .network-container 
    {
      padding: 14px 24px 16px 24px;
    }

    .media-container 
    {
      padding: 14px 24px;
    }

    .clock-time-row 
    {
      margin-bottom: 10px;
    }

    .clock-label-hours,
    .clock-label-minutes 
    {
      font-family: "${fontClockDisplay}";
      font-size: 76px;
      font-weight: bold;
      color: ${palette.base0D};
    }

    .clock-label-separator 
    {
      font-family: "${fontClockDisplay}";
      font-size: 60px;
      font-weight: bold;
      color: ${palette.base03};
      margin: 0 4px;
    }

    .clock-label-weekday 
    {
      font-family: "${fontClockDisplay}";
      font-size: 22px;
      font-weight: bold;
      letter-spacing: 4px;
      color: ${palette.base0D};
      margin-bottom: 6px;
    }

    .clock-label-date 
    {
      font-family: "${fontMonospace}";
      font-size: 15px;
      letter-spacing: 1px;
      color: ${palette.base03};
    }

    .network-header 
    {
      margin-bottom: 6px;
    }

    .network-interface-id 
    {
      font-family: "${fontMonospace}";
      font-size: 12px;
      letter-spacing: 1px;
      color: ${palette.base03};
    }

    .network-metric-rx 
    {
      font-family: "${fontMonospace}";
      font-size: 13px;
      color: ${palette.base0B};
      margin-right: 12px;
    }

    .network-metric-tx 
    {
      font-family: "${fontMonospace}";
      font-size: 13px;
      color: ${palette.base0E};
    }

    .network-throughput-graph 
    {
      color: ${palette.base0D};
      background-color: transparent;
      margin-top: 2px;
    }

    .media-artwork-frame 
    {
      min-width: 60px;
      min-height: 60px;
      border-radius: 12px;
      background-color: rgba(${paletteRgb.base02-dec-r}, ${paletteRgb.base02-dec-g}, ${paletteRgb.base02-dec-b}, 0.5);
    }

    .media-artwork-image 
    {
      border-radius: 12px;
    }

    .media-artwork-placeholder 
    {
      font-family: "${fontMonospace}";
      font-size: 26px;
      color: ${palette.base03};
    }

    .media-player-name 
    {
      font-family: "${fontMonospace}";
      font-size: 10px;
      letter-spacing: 2px;
      color: ${palette.base03};
    }

    .media-track-title 
    {
      font-family: "${fontClockDisplay}";
      font-size: 14px;
      font-weight: bold;
      color: ${palette.base05};
    }

    .media-progress-bar trough 
    {
      min-height: 3px;
      border-radius: 2px;
      background-color: rgba(${paletteRgb.base02-dec-r}, ${paletteRgb.base02-dec-g}, ${paletteRgb.base02-dec-b}, 0.8);
    }

    .media-progress-bar highlight 
    {
      min-height: 3px;
      border-radius: 2px;
      background-color: ${palette.base0D};
    }

    .media-progress-bar slider 
    {
      all: unset;
      min-width: 0px;
      min-height: 0px;
      background-color: transparent;
    }

    .media-controls-row 
    {
      margin-top: 4px;
    }

    .media-time-elapsed 
    {
      font-family: "${fontMonospace}";
      font-size: 10px;
      color: ${palette.base03};
    }

    .media-control-button 
    {
      font-family: "${fontMonospace}";
      font-size: 14px;
      color: ${palette.base0D};
      padding: 0 3px;
    }

    .media-control-button:hover 
    {
      color: ${palette.base05};
    }
  '';
}
