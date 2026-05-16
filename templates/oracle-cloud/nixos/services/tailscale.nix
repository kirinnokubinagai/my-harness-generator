{ config, pkgs, lib, ... }:

{
  services.tailscale = {
    enable = true;
    authKeyFile = "/home/opc/.tailscale-authkey";  # scp'd by setup-oci-vm-nixos.sh, chmod 600
    extraUpFlags = [
      "--ssh"                       # Tailscale SSH (ACL-based, replaces raw sshd exposure)
      "--accept-dns=false"          # don't override the VM's resolv.conf
      "--hostname=harness-oci"
    ];
    useRoutingFeatures = "server";
  };

  # Tailscale uses UDP 41641 for direct P2P; falls back to DERP (TCP/443)
  # if that's blocked. Allow the UDP port through the NixOS firewall.
  networking.firewall.allowedUDPPorts = [ 41641 ];

  # Trust the tailscale0 interface so intra-tailnet traffic isn't
  # filtered by the host firewall.
  networking.firewall.trustedInterfaces = [ "tailscale0" ];

  # State at /var/lib/tailscale persists across reboot (NixOS default).
  # No re-auth needed unless the tagged auth key is rotated.
}
