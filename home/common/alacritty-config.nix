{
  colors = {
    primary = {
      background = "#ffffff";
      foreground = "#24292f";
    };
    normal = {
      black = "#24292e";
      red = "#d73a49";
      green = "#28a745";
      yellow = "#dbab09";
      blue = "#0366d6";
      magenta = "#5a32a3";
      cyan = "#0598bc";
      white = "#6a737d";
    };
    bright = {
      black = "#959da5";
      red = "#cb2431";
      green = "#22863a";
      yellow = "#b08800";
      blue = "#005cc5";
      magenta = "#5a32a3";
      cyan = "#3192aa";
      white = "#d1d5da";
    };
    indexed_colors = [
      {
        index = 16;
        color = "#d18616";
      }
      {
        index = 17;
        color = "#cb2431";
      }
    ];
  };
  font.normal.family = "DejaVuSansM Nerd Font Mono";
  keyboard.bindings = [
    {
      key = "+";
      mods = "Control|Shift";
      action = "IncreaseFontSize";
    }
  ];
}
