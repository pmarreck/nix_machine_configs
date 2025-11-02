{ lib, buildGoModule, installShellFiles }:

let
  src = builtins.fetchGit {
    url = "https://github.com/opencode-ai/opencode";
    ref = "main";
    rev = "73ee493265acf15fcd8caab2bc8cd3bd375b63cb";
  };

  shortRev =
    lib.optionalString (src ? rev)
      (lib.substring 0 7 src.rev);

  version =
    if shortRev == ""
    then "unstable"
    else "unstable-${shortRev}";
in
buildGoModule {
  pname = "opencode";
  inherit version src;

  vendorHash = "sha256-Kcwd8deHug7BPDzmbdFqEfoArpXJb1JtBKuk+drdohM=";

  subPackages = [ "." ];

  nativeBuildInputs = [
    installShellFiles
  ];

  ldflags = [
    "-s"
    "-w"
  ];

  postInstall = ''
    installShellCompletion --cmd opencode \
      --bash <($out/bin/opencode completion bash) \
      --fish <($out/bin/opencode completion fish) \
      --zsh <($out/bin/opencode completion zsh)
  '';

  meta = with lib; {
    description = "AI coding agent built for the terminal";
    homepage = "https://github.com/opencode-ai/opencode";
    license = licenses.mit;
    mainProgram = "opencode";
    platforms = platforms.linux;
  };
}
