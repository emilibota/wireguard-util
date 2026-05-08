# wireguard-util

Easy way to setup WireGuard on servers (server-to-server connections).

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/emilibota/wireguard-util/main/install.sh | bash
```

This installs `wgu` (a wrapper for `wg-util.sh`) into your PATH and sets up shell completions for bash and zsh.

To install from a local clone:

```sh
bash install.sh
```

## Uninstall

```sh
curl -fsSL https://raw.githubusercontent.com/emilibota/wireguard-util/main/uninstall.sh | bash
```

Or from a local clone:

```sh
bash uninstall.sh
```

This removes `wg-util.sh`, the `wgu` wrapper, and the shell completion files, and cleans the sourcing lines added to `~/.bashrc` and `~/.zshrc`.

---

## Server setup

Initialize the WireGuard server:

```sh
wgu set-server
```

Add a client peer to the server:

```sh
wgu create-client john_doe_pc
```

This prints the client config, saves it to `/etc/wireguard/john_doe_pc.conf`, and outputs a one-liner to run on the client machine:

```sh
curl -fsSL https://raw.githubusercontent.com/emilibota/wireguard-util/main/wg-util.sh | bash -s -- setup-client -e 1.2.3.4:51820 -i 10.8.0.2 -s <server_pubkey>
```

## Client setup

Run the one-liner printed by `create-client` on the client machine, or manually:

```sh
wgu setup-client -e <SERVER_IP:PORT> -i <CLIENT_IP> -s <SERVER_PUBKEY>
```

Missing flags (`-e`, `-i`, `-s`) are prompted interactively. The server public key input is hidden.

This generates a keypair, writes `/etc/wireguard/wg0.conf`, brings up the interface, and prints the client public key to add on the server.

AllowedIPs defaults to the WireGuard subnet (e.g. `10.8.0.0/24`) — traffic is routed only within the VPN, not through it.

## Client lifecycle

```sh
wgu client-status       # wg show
wgu client-disconnect   # wg-quick down
wgu client-enable       # enable on boot (systemctl)
wgu client-disable      # disable on boot
```

## Other commands

```sh
wgu get-port            # print server listen port
wgu get-ip              # print server IP
wgu remove-client NAME  # remove a peer from server config
```

## Shell completions

Completions are installed automatically by `install.sh`. To generate them manually:

```sh
wgu completions bash    # bash
wgu completions zsh     # zsh
```

## Full usage

```
wgu [-y] [-c NAME] set-server [-p PORT] [-i IP] [-pv FILE] [-pu FILE] [-d DIR]
wgu [-y] [-c NAME] get-port [-d DIR]
wgu [-y] [-c NAME] get-ip [-d DIR]
wgu [-y] [-c NAME] create-client CLIENT [-i IP] [--dns DNS] [-d DIR]
wgu [-y] [-c NAME] remove-client CLIENT [-d DIR]
wgu [-y] [-c NAME] setup-client [-e ENDPOINT] [-i IP] [-s SERVER_PUBKEY] [--dns DNS] [--keepalive N] [--allowed-ips IPs] [-d DIR]
wgu [-c NAME] client-disconnect
wgu [-c NAME] client-status
wgu [-c NAME] client-enable
wgu [-c NAME] client-disable
wgu completions [bash|zsh]
```

Global flags: `-y` auto-installs WireGuard without prompting; `-c NAME` sets the interface name (default `wg0`).

Cheers 🍻
