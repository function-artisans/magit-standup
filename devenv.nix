{ pkgs, ... }:

{
  packages = [
    pkgs.emacs-nox
    pkgs.eask-cli
  ];

  git-hooks.hooks = {
    actionlint.enable = true;
    statix.enable = true;
    deadnix.enable = true;
    nixfmt.enable = true;
    check-yaml.enable = true;
    check-merge-conflicts.enable = true;
    typos.enable = true;
    ripsecrets.enable = true;
  };

  enterTest = ''
    eask install-deps
    eask compile
    eask lint package
    eask test buttercup
  '';
}
