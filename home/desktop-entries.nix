# desktop-entries.nix by poligle

{ config, pkgs, lib, ... }:
let
  hidden = name: {
    text = ''
      [Desktop Entry]
      Type=Application
      Name=${name}
      NoDisplay=true
    '';
  };
in
{
  # Hide unwanted launcher entries by overriding them in the user's
  # applications dir (~/.local/share/applications), which takes precedence.
  xdg.dataFile = {
    "applications/code-url-handler.desktop" = hidden "Visual Studio Code - URL Handler";
    "applications/kitty-open.desktop" = hidden "kitty URL Launcher";
    "applications/org.freedesktop.Xwayland.desktop" = hidden "Xwayland";
    "applications/xdg-desktop-portal-gtk.desktop" = hidden "Portal";
    "applications/nixos-manual.desktop" = hidden "NixOS Manual";
    "applications/uuctl.desktop" = hidden "uuctl";
    "applications/kitty.desktop" = hidden "kitty";
    "applications/nvim.desktop" = hidden "Neovim wrapper";
    "applications/nm-applet.desktop" = hidden "NetworkManager Applet";
    "applications/nm-connection-editor.desktop" = hidden "Advanced Network Configuration";
    "applications/blueman-adapters.desktop" = hidden "Bluetooth Adapters";
    "applications/blueman-manager.desktop" = hidden "Bluetooth Manager";
    "applications/org.pulseaudio.pavucontrol.desktop" = hidden "Volume Control";
    "applications/thunar-bulk-rename.desktop" = hidden "Bulk Rename";
    "applications/thunar-settings.desktop" = hidden "Thunar Preferences";
    "applications/thunar-volman-settings.desktop" = hidden "Removable Drives and Media";

    # LibreOffice
    "applications/startcenter.desktop" = hidden "LibreOffice";
    "applications/draw.desktop" = hidden "LibreOffice Draw";
    "applications/impress.desktop" = hidden "LibreOffice Impress";
    "applications/math.desktop" = hidden "LibreOffice Math";
    "applications/base.desktop" = hidden "LibreOffice Base";
    "applications/xsltfilter.desktop" = hidden "LibreOffice XSLT based filters";
  };
}
