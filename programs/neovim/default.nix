{ pkgs, ... }:
let allPlugins = pkgs.vimPlugins // pkgs.callPackage ./custom-plugins.nix { };
in {
  programs.neovim = {
    enable = true;

    withPython = true;
    withPython3 = true;
    withRuby = true;
    withNodeJs = true;

    vimAlias = true;

    extraConfig = builtins.readFile ./vimrc;

    plugins = with allPlugins; [
      ale
      candid
      fzfWrapper
      fzf-vim
      gitgutter
      goyo
      gv
      lightline-vim
      neoformat
      polyglot
      quickfix-reflector
      tabnine
      todo
      unimpaired
      vim-abolish
      vim-commentary
      vim-eunuch
      vim-fugitive
      vim-highlightedyank
      vim-localvimrc
      vim-repeat
      vim-rhubarb
      vim-signature
      vim-speeddating
      vim-surround
      vim-test
      vim-vinegar
      visual-star-search
    ];
  };
}
