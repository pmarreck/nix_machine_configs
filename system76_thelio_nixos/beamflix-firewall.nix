# Receiver ingress for Mecha BeamFlix: receivers connect back to the sender.
# TCP 7170 is the media server every receiver fetches movies from.
# UDP 7171 is AirPlay timing: an Apple TV does not answer setup until it can reach it.
# UDP 7172 takes DLNA search replies.
# Peter approved these three ports on all interfaces 2026-10-28.
{ ... }:
{
  networking.firewall.allowedTCPPorts = [ 7170 ];
  networking.firewall.allowedUDPPorts = [ 7171 7172 ];
}
