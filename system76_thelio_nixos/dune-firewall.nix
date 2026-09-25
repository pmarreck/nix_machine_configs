# Player ingress for the Dune: Awakening world on this host.
# UDP 7777 is the game. TCP 31982 is the game broker (AMQPS).
# Admin UI, Postgres, and the admin RabbitMQ stay closed.
# Peter approved these two ports 2026-09-24. UDP 7888 is server-to-server
# and is not opened here.
{ ... }:
{
  networking.firewall.allowedTCPPorts = [ 31982 ];
  networking.firewall.allowedUDPPorts = [ 7777 ];
}
