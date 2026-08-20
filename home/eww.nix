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

in
{
  home.packages = 
  [
    pkgs.eww
    pkgs.poppins
    ewwNetworkMonitor
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
  '';
}