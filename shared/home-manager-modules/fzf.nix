{ pkgs, ... }: {
  programs.fzf = {
    enable = true;
    enableFishIntegration = true;
    defaultCommand = "${pkgs.ripgrep}/bin/rg --hidden --iglob !.git --files";
  };
}
