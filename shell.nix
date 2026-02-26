{ pkgs ? import <nixpkgs> { config.allowUnfree = true; } }:

pkgs.mkShell {
  buildInputs = with pkgs; [
    cudaPackages.cudatoolkit
    gcc
    bear
  ];

  shellHook = ''
    export CUDA_PATH=${pkgs.cudaPackages.cudatoolkit}
  '';
}
