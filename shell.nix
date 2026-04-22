{ pkgs ? import <nixpkgs> { config.allowUnfree = true; } }:
pkgs.mkShell {
	buildInputs = with pkgs; [
		cudaPackages.cudatoolkit
		gcc
		bear
		python3
	];

	shellHook = ''
		export CUDA_PATH=${pkgs.cudaPackages.cudatoolkit}
		export LD_LIBRARY_PATH=/run/opengl-driver/lib:$LD_LIBRARY_PATH
	'';
}
