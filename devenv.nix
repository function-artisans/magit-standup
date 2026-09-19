{ pkgs, ... }:

{
  packages = [
    pkgs.emacs-nox
    pkgs.eask-cli
  ];

  enterTest = ''
    eask install-deps
    eask compile
    eask lint package
    eask test buttercup
  '';
}
