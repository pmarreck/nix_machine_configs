# Route aarch64-darwin Mechatron builds to Peter's Mac.
#
# The private key at sshKey is root-only and is not in git. It was generated
# on Thelio and installed in pmarreck@m4max authorized_keys. publicHostKey is
# base64 of the Mac's ssh_host_ed25519_key.pub, including its trailing newline.
# Rollback: drop this import and reify. The previous NixOS generation stays
# bootable. Removing the Mac authorized_keys line is a separate step.
{ ... }:
{
  nix.distributedBuilds = true;
  nix.settings.builders-use-substitutes = true;
  nix.buildMachines = [
    {
      hostName = "m4max.tail66c90.ts.net";
      protocol = "ssh-ng";
      sshUser = "pmarreck";
      sshKey = "/etc/mechatron-prime/mac-builder/id_ed25519";
      systems = [ "aarch64-darwin" ];
      # Leave the interactive Mac usable. Darwin jobs do not compete with
      # Thelio's x86_64-linux max-jobs.
      maxJobs = 4;
      speedFactor = 2;
      publicHostKey = "c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSU9MZzRmd2JrckMyTGI2ODhOc0R6YnlVS1RML3NXbWJuQ3NDdjdtT1hCNzcgCg==";
    }
  ];

  programs.ssh.knownHosts.m4max-darwin-builder = {
    hostNames = [ "m4max.tail66c90.ts.net" "m4max" ];
    publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOLg4fwbkrC2Lb688NsDzbyUKTL/sWmbnCsCv7mOXB77";
  };
}
