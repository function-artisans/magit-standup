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
    eask --strict compile
    eask --strict lint package
    eask --strict lint regexps
    eask --strict lint declare
    eask --strict lint org README.org
    eask test buttercup
  '';
}
