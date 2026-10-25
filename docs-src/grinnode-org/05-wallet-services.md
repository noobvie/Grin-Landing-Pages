---
title: Wallet & payment services
description: The wallet hub — what a Grin wallet is, the fixed-slot menu, every wallet and payment product with its status, and the CMD wallet quick setup step by step.
section: Scripts
order: 5
short: CMD wallet
label: Script 05
covers: 2026-10-23
updated: 2026-10-24
---

Main-menu option **5** opens the wallet hub: one screen that shows which wallet and payment products are installed and running on the server, and launches the one you pick. Each product is its own script with its own wallet, ports, nginx site and service. The hub itself installs nothing — except the **CMD Wallet quick setup**, which is built into it and is the fastest way to get a working command-line wallet next to your node.

> **Warning:** Status — the main menu marks this hub **(DEV)**. Two of its products are ready to use (the CMD wallet and Grin Drop); the rest are marked *building* on the hub screen, and one — Accio — has never run on a server at all (see [Accio](#accio-the-public-web-wallet-not-yet-run) below). Rehearse anything wallet-related on **testnet** first: the toolkit runs both networks side by side precisely so you can.

## A Grin wallet, in plain words

The **node** (from [Script 01](01-build-node.html)) keeps a copy of the chain and talks to other nodes. It holds no coins and no keys. A **wallet** is a separate program — `grin-wallet` — that holds a secret **seed**, derives keys from it, asks a node what is on the chain, and builds transactions. On this toolkit the wallet always talks to a node over the node's Foreign API (port 3413, testnet 13413); it can be your own node on the same server or a public node such as those [Script 04](04-publish-node-api.html) publishes.

Three things about Grin surprise people coming from Bitcoin:

- **There are no addresses on the chain.** Nothing you receive is "sent to an address" that anyone can look up. A Grin wallet does have an address — a **[Slatepack address](reference-glossary.html#slatepack-address)**, `grin1…` on mainnet and `tgrin1…` on testnet — but it is a key for *talking to* the wallet, not a destination on the ledger.
- **Every transaction is a two-way exchange.** The sender's wallet produces a partial transaction (a **[slate](reference-glossary.html#slate-and-slatepack)**), the receiver's wallet signs it and hands it back, and the sender finalises and broadcasts it. Both wallets take part. That exchange can happen automatically when both are online, or by hand: the slate travels as a block of text called a **slatepack** that you copy and paste — in a chat, an email, on paper.
- **Coins that are sent to you need your wallet to answer.** A wallet that is *listening* — running with its Foreign API open, ideally reachable over Tor at its slatepack address — receives without you doing anything. A wallet that is switched off receives nothing until the sender reaches it another way.

The toolkit's wallets move slates three ways: **Tor** (both wallets online; the sender connects to the receiver's address over the [Tor network](reference-glossary.html#tor-and-onion-addresses)), **slatepack** text (copy and paste, either side may be offline), and — for products that support it — the **Transporter**, a store-and-forward queue from the [Connectivity Hub](09-connectivity-hub.html#grin-transporter-093) (main menu 9) so the receiver can be offline at send time.

Two more terms you will meet on every wallet screen. The **[seed phrase](reference-glossary.html#seed-phrase)** — 24 words printed once when the wallet is created — *is* the wallet; anyone holding it holds the coins, and it is the only way to recover them on another machine. The **[passphrase](reference-glossary.html#passphrase)** encrypts the seed file on disk and is asked for every time the wallet is unlocked. The wallet exposes two local APIs of its own: the **Foreign API** (port 3415 / 13415) through which it receives, and the **Owner API** (3420 / 13420) through which it is managed; both stay on localhost and are never opened to the internet.

## What the hub does

1. Probes each product — a config file for *installed*, a [systemd unit](reference-glossary.html#systemd-service) or tmux session for *running* — and prints a status line for every one it finds. A fresh server shows `No wallet services installed yet.` WooCommerce never appears in that list, even when installed and running: the hub looks for `grin-wallet-bridge-<net>` units, while Script 053 creates `grin-woo-bridge-<net>` — check it from 053's own menu instead.
2. Shows the menu below. Every key is live: a product key launches that product's script; a *planned* or *spare* key prints one screen explaining what the slot is for and returns, having installed nothing.
3. Runs the CMD Wallet quick setup itself when you press `A`.

The hub prints a tip worth taking seriously: **install each service on its own server.** Every wallet product wants the wallet ports 3415 and 3420 (13415 / 13420 on testnet); two of them on one box collide, and a wallet holding real funds next to a public web service is a security mix you do not need. One server can still run the mainnet *and* testnet copies of a product together.

## The menu

This hub is the one place in the toolkit where menu keys are **fixed slots** and can be quoted safely: each category owns a block of keys ending in a spare, and a row keeps its key permanently — a new wallet takes slot `4`, a new payment rail slot `8`, and nothing below moves.

```text
 05) GRIN WALLET & PAYMENT SERVICES

  Tip: Install each service on its own dedicated server.
       Mixing services on one machine risks port conflicts,
       config collisions, and harder security isolation.
       Each server can run both mainnet and testnet together.

  No wallet services installed yet.

  ✅ ready   🔧 building   ⏳ planned — a planned key explains the slot, installs nothing

  ── Wallets ──────────── hold & spend your own GRIN

  A) CMD Wallet Quick Setup  ✅  download · init/recover · listen (CLI/testing)
  1) Fidelius                🔧  personal web wallet · server-held keys
  2) Accio                   🔧  public web wallet · client-side keys
  3) Grin XP                 🔧  Fidelius, XP-themed · mainnet only
  4) Spare slot                  unassigned · next wallet lands here

  ── Accept Payments ──── receive GRIN from customers

  5) WooCommerce Gateway     🔧  WordPress/WooCommerce plugin
  6) Payment Pro             ⏳  Shopify / custom REST API
  7) GoblinPay               ⏳  receive-only merchant till
  8) Spare slot                  unassigned · next payment rail lands here

  ── Giveaways & Donations ─ hand GRIN out

  9) Grin Drop               ✅  giveaway faucet + donation portal

  Grin Transporter moved → main menu 09 (Grin Connectivity Hub)

  0) Back to main menu

Select [A / 1-9 / 0]:
```

| Key | Product | What it is, and who it is for | Status · manual |
|-----|---------|-------------------------------|-----------------|
| `A` | **CMD Wallet quick setup** (05C) | Downloads `grin-wallet`, creates or recovers a wallet, points it at your node and starts a listener in tmux. For anyone who wants a wallet on the command line — testing, everyday use over SSH, or the wallet behind the Transporter agent | ✅ ready · [below](#the-cmd-wallet-quick-setup) |
| `1` | **Fidelius** (051) | A browser wallet for your own server: one Node.js service, many wallets, both networks, behind nginx + [Basic Auth](reference-glossary.html#basic-auth) + HTTPS. The **server holds the keys**. For the server owner, and only them | 🔧 building · [Fidelius](051-fidelius.html) |
| `2` | **Accio** (052) | A public, self-custodial web wallet: keys are generated and kept in the visitor's browser tab; the server holds no seed. For operators who want to offer a wallet to the public | 🔧 **never run on a server** · [status below](#accio-the-public-web-wallet-not-yet-run) |
| `3` | **Grin XP** (051x) | A wallet UI dressed as a Windows XP desktop — mainnet only, its own nginx site, a separate PHP code base from Fidelius. For fun; the theme is cosmetic, the GRIN is real | 🔧 building · [Fidelius → Grin XP](051-fidelius.html#grin-xp-the-xp-themed-variant) |
| `4` | *Spare* | Prints a notice; installs nothing | — |
| `5` | **WooCommerce Gateway** (053) | A WordPress/WooCommerce plugin plus a Node bridge to a wallet on this server, so a shop can take GRIN with a slatepack [invoice](reference-glossary.html#invoice) flow. For merchants running WooCommerce | 🔧 building · [WooCommerce](053-woocommerce.html) |
| `6` | *Payment Pro* | Planned: a payment processor for Shopify and custom REST APIs. Prints a notice; installs nothing | ⏳ planned |
| `7` | *GoblinPay* | Planned: a receive-only merchant till (Nostr + slatepack) deploying [2ro's GoblinPay](https://github.com/2ro/GoblinPay). Prints a notice; installs nothing | ⏳ planned |
| `8` | *Spare* | Prints a notice; installs nothing | — |
| `9` | **Grin Drop** (059) | A giveaway faucet and donation portal with a rate-limited claim flow and a donation address + QR — [drop.grin.money](https://drop.grin.money). For anyone handing GRIN out: events, promotions, tips | ✅ ready · [Grin Drop](059-grin-drop.html) |
| `0` | Back | | |

`C` still works as a silent alias for `A` — it was the CMD wallet's key for a long time. The **script number** in brackets is what the repository files and the toolkit's design documents use; it is printed on each product's own banner (`051) FIDELIUS …`), never on the hub row, and it is *not* the menu key — key `5` opens script 053, key `9` opens 059.

## The CMD Wallet quick setup

The CMD wallet is the plain `grin-wallet` binary, set up in `/opt/grin/cmdwallet/<network>/` and left running as a **listener** in a tmux session so it can receive. There is no web page; you use it from the shell. It is the right first wallet to make: it exercises the same node link every other product depends on, and its screen tells you in plain terms whether that link works.

```text
 05C) GRIN WALLET QUICK SETUP

  Download, init or recover, then start a listener — for direct CLI use,
  testing, or as the wallet behind the Script 093 Transporter agent.
  Setup asks which mode: 'listen' (Foreign 3415/13415, receive-only, Tor
  onion automatic) or 'owner_api' (Owner v3 + Foreign on 3420/13420, can
  also SEND, no automatic Tor). The passphrase is fed on stdin, never via
  -p, so it never appears in ps/cmdline.
  Stored in /opt/grin/cmdwallet/<net>/ — independent of other services.

  No cmd wallet installed yet.

  1) Mainnet  (real GRIN)
  2) Testnet  (tGRIN — no monetary value)
  3) Both

  B) grin-wallet binary  (update · roll back · verify)
  L) Listener            (start · stop · restart · recent output)
  N) Nuke wallet         (stop + remove one network's wallet, for a fresh test)
  0) Back

Select [1/2/3/B/L/N/0]:
```

| Key | Action |
|-----|--------|
| `1` / `2` / `3` | Set up the mainnet wallet, the testnet wallet, or both in turn — the step table below |
| `B` | The `grin-wallet` binary screen for one network: install, update, roll back, verify |
| `L` | [The listener screen](#the-listener-screen-l) — start, stop or restart a wallet's listener without walking through setup again |
| `N` | [Nuke](#nuke-start-a-network-over-n) — stop one network's wallet and remove it, so the next setup starts clean |
| `0` | Back to the hub |

Once a wallet exists the screen shows one line per network — listening, alive-but-not-bound (typically after switching modes and declining the restart), or installed but stopped:

```text
  ● mainnet  listening  listen :3415 · tmux: grin_mainnet_cmd_wallet
  ▲ testnet  session up, port 13420 not bound  mode owner_api — restart it
  ○ testnet  installed · not listening · mode listen
```

### The two listener modes

Every network's wallet runs in one of two modes, chosen during setup and remembered in `.listen_mode`:

| Mode | Port | What it can do | Tor |
|------|------|----------------|-----|
| **`listen`** (default) — `grin-wallet listen` | Foreign API on **3415** / 13415 | **Receive only.** Other wallets can pay you; nothing can drive a *send* through this process | grin-wallet starts its own Tor for the listener, so the wallet is reachable at its `grin1…` address over Tor with nothing else to configure |
| **`owner_api`** — `grin-wallet owner_api` | Owner + Foreign API together on **3420** / 13420 | Receive **and** send, driven over HTTP. Required by anything that operates the wallet programmatically — the Transporter agent from the Connectivity Hub (main menu 9) cannot send through `listen` at all | **No automatic Tor listener** in this mode |

Pick `listen` unless something needs to send *through* the wallet for you. You can switch later by re-running the setup and keeping the existing wallet.

> **Note:** Which Tor `listen` uses depends on the wallet's `grin-wallet.toml`. A wallet created by v5.5.0 gets `use_integrated = true` under `[tor]`, so grin-wallet runs a Tor client built into itself (Arti); a toml written by an older release has no such key and keeps launching the system `tor` binary, which must then be installed. Either way the onion address comes from the wallet seed. This is read from the toolkit's notes on the upstream release, not observed on a server.

### Setup, step by step

Pick `1`, `2` or `3` (mainnet first, then testnet). The script shows the target — network, node port, current listener mode, the wallet directory, the binary, the passphrase and seed file paths, the tmux session name — and runs these steps. Every prompt accepts `0` to cancel.

| Step | What happens | What you do |
|------|--------------|-------------|
| 1 | **Binary.** Downloads the pinned `grin-wallet` release (**v5.5.0**) from GitHub into the shared version store `/opt/grin/wallet-bin/<tag>/`, verifies its SHA256, and copies it to `/opt/grin/cmdwallet/<network>/grin-wallet`. If a binary is already there: `Re-install the pinned v5.5.0? [y/N/0 cancel]` | Enter |
| 2 | **Init or recover.** If a wallet already exists: `Re-initialize? (replaces the existing wallet!) [y/N/0 cancel]` — `N` keeps it and the rest of the steps re-apply the config to it. Next comes `1) New wallet` or `2) Recover from seed`, and for a new wallet the passphrase, typed twice (hidden). Only then, if you answered `y`, is the old wallet replaced: the screen warns if a Transporter agent is wired to it, a **mainnet** wallet asks you to type `MAINNET` and is then *moved* to `/opt/grin/cmdwallet/.retired/mainnet-<date_time>/`, and a **testnet** wallet is deleted. A `0` up to that point changes nothing; a `0` at any later prompt (steps 3–4) does not bring the old wallet back. If the directory holds a `grin-wallet.toml` but no `wallet_data/wallet.seed` (an earlier init that did not finish), the script says `Half-initialized wallet` and clears it with no `Re-initialize?` and no `MAINNET` question (on mainnet it is moved to `.retired/` too). Then `1` runs `grin-wallet init -h` with your passphrase on stdin, and grin-wallet prints the **24-word seed phrase**; `2` runs `grin-wallet init -hr`, and grin-wallet itself prompts you on the terminal for the phrase and a new passphrase. Success is judged by `wallet_data/wallet.seed` appearing | **Write the seed phrase down** — it is shown once. `Enter a wallet passphrase` twice |
| 3 | **Save the passphrase?** `[Y/n]` — default **yes**, to `<network>_pass_wallet.txt`, root-only (mode 600). Without it the listener asks for the passphrase at every start and cannot come back unattended after a crash. After a recovery, or on an existing wallet with no saved copy, the script asks for the passphrase and **verifies it opens the wallet** before writing it | Enter, or `n` if you prefer to type it at every start |
| 4 | **Save the seed phrase?** `[y/N]` — default **no**. A plaintext mnemonic beside the wallet it unlocks defeats the passphrase; say yes only if you know why you want a copy at `<network>_seed.txt` (mode 600) | Enter |
| 4b | **Listener mode.** `1) listen` or `2) owner_api`; Enter keeps the current mode. A running listener in the old mode is restarted on the new port at step 7 | Pick — see the table above |
| 5 | **Config.** Patches `grin-wallet.toml`: `node_api_secret_path` → the live node's `.foreign_api_secret`; `api_listen_port` = 3415 / 13415 and `owner_api_listen_port` = 3420 / 13420 (grin-wallet writes mainnet ports even for testnet, so both are pinned every time); `owner_api_include_foreign = true` for owner_api mode; `log_max_files = 5`. Registers the directory in `/opt/grin/conf/grin_wallets_location.conf` so **Admin & Maintenance → Backup** includes it, and installs the 5-minute `grin-secret-sync` timer that re-points the wallet at the node after a node rebuild | Nothing |
| 6 | **Checks.** `grin-wallet address` (a local operation — proves the passphrase), then `grin-wallet info` (refreshes against the node — the only step that proves the **wallet → node link** works; capped at 90 s). Skipped if a listener already holds the wallet, or if the passphrase was not saved | Read the result |
| 7 | **Listener.** Refuses if another process holds the port (it never kills it — it may be a wallet with funds). If this wallet's session already exists: `Kill and restart? [y/N/0 skip]`. Writes `listen.sh`, starts it in the tmux session `grin_<network>_cmd_wallet`, waits up to 15 s for the port | `y` to restart after a mode change |
| — | **Summary.** Ten rows numbered 1–9 plus 5b (binary, init, passphrase, seed, node secret, mode, ports, checks, listener, backup registration), the wallet address, quick-reference commands, and a pointer to `L) Listener` for later restarts | Read it |

> **Note:** During `init` grin-wallet may print `get_version: Cannot parse response`. That is **harmless**: init runs before step 5 gives the wallet the node's secret, so its version probe fails, but the seed is written all the same. Only `info` in step 6 tells you whether the wallet can really reach the node.

With `3) Both`, testnet setup starts automatically after mainnet finishes.

### After it finishes

```bash
tmux ls                                        # grin_mainnet_cmd_wallet
tmux attach -t grin_mainnet_cmd_wallet         # the listener's output; Ctrl+B then D to detach
```

A healthy `listen`-mode session shows grin-wallet starting the Foreign listener on `127.0.0.1:3415` and, a little later, a Tor `.onion` (the wallet's slatepack address in onion form). Balance and history come from the wallet's own commands, run from the wallet directory (add `--testnet` for the testnet wallet); each asks for the passphrase:

```bash
cd /opt/grin/cmdwallet/mainnet
./grin-wallet info        # balance: total, awaiting confirmation, currently spendable
./grin-wallet address     # your grin1… slatepack address — give this to people paying you
./grin-wallet txs         # transaction history
```

To pay someone, `./grin-wallet send -d <address> <amount>` (their `grin1…` address) tries to reach them over Tor and, if it cannot, prints a slatepack for you to pass on by hand; they run `receive`, send the reply back, and you `finalize` it. The full command-line flow is in the [Grin wallet documentation](https://docs.grin.mw/wiki/wallet/grin-wallet-usage/).

> **Note:** The script's own comments say a running listener holds the wallet database lock, so a second `grin-wallet` command in the same directory may block until it times out. If `info` hangs, stop the listener first (`L` → `2) Stop`), run the command, then start it again (`L` → `1) Start`). This was taken from the code, not observed on a server.

#### What was created

| Path | Purpose |
|------|---------|
| `/opt/grin/cmdwallet/<network>/grin-wallet` | The wallet binary, a copy of `/opt/grin/wallet-bin/<tag>/grin-wallet` |
| `…/grin-wallet.toml` | Wallet configuration, patched in step 5 |
| `…/wallet_data/wallet.seed` | The encrypted seed — the file that *is* your wallet. Back it up (**[Admin & Maintenance → Backup](089-backup-restore.html)** does — but its restore menu does not put this directory back; that page shows the manual step) |
| `…/<network>_pass_wallet.txt` | The saved passphrase (if you agreed), mode 600 |
| `…/<network>_seed.txt` | The plaintext seed phrase (only if you asked for it), mode 600 |
| `…/.listen_mode` | `listen` or `owner_api` |
| `…/listen.sh` | The generated launcher the tmux session runs; it feeds the passphrase on stdin, never on the command line |
| `…/.grin-wallet.version` | Which binary version is installed and which one to roll back to |
| `/opt/grin/wallet-bin/<tag>/` | The shared, verified binary store used by every wallet product on the box |
| `/opt/grin/conf/grin_wallets_location.conf` | `CMDWALLET_<NETWORK>_WALLET_DIR="…"` — how the backup script finds the wallet |
| tmux session `grin_<network>_cmd_wallet` | The listener. It lives on **root's** tmux server (plain `tmux ls`), unlike the node sessions, which are on the `grin` user's (`gtmux ls`) |
| `/opt/grin/cmdwallet/.retired/mainnet-<date_time>/` | Only after a mainnet re-initialize, a half-initialized clean-up or a Nuke: the old wallet, moved here (mode 700) instead of deleted, with its saved passphrase and seed files if it had them. Not registered for backup — copy it off the server or purge it yourself |

### The listener screen (L)

`L` opens a small screen for one network's listener (it asks which network only when both have a wallet). It changes no configuration — mode, ports and the toml stay the setup flow's job — and uses the same start and stop code as setup:

```text
 CMD Wallet — Listener · MAINNET

  Listener   : ● listening  :3415 · PID 12345 · up 02:14:07
  Mode       : listen — Foreign API 3415
  Passphrase : saved — starts unattended
  tmux       : grin_mainnet_cmd_wallet

  1) Start
  2) Stop
  3) Restart
  4) Recent output  (log + tmux pane, without attaching)
  0) Back

Select [1-4/0]:
```

| Key | Action |
|-----|--------|
| `1` | Starts the listener: the saved passphrase if there is one (otherwise it asks), the same port guard as setup, the same `listen.sh` launcher |
| `2` | Stops the tmux session **and** every `grin-wallet` process whose working directory is this wallet's folder — including one you started by hand outside tmux. It waits up to 10 s, then sends TERM, then KILL. It never touches a process that merely holds the port from somewhere else |
| `3` | Stop, then Start. Because Stop waits for the wallet's own processes to exit, the new listener never fights the old one for the wallet's database lock |
| `4` | The last 25 lines of the wallet's log file and the last 15 lines of its tmux pane, plus the commands to follow them live. In a live `tmux attach`, detach with Ctrl+B then D — **Ctrl+C stops the listener** |

The status line also catches the case the main screen cannot see: `▲ grin-wallet running outside tmux` means the wallet was started by hand (for example by running `listen.sh` in the foreground); `2) Stop` clears it.

### Nuke: start a network over (N)

`N` removes one network's CMD wallet so the next setup starts from nothing — useful when testing. It asks for the network, shows what it found (whether a seed exists, whether the listener runs, whether a saved seed copy is on the box), and collects every answer before it touches anything:

1. `Keep the grin-wallet binary, so setup skips the download? [Y/n]` — `Y` keeps the binary and its version record.
2. `Nuke the <network> CMD wallet? [y/N]`, and on mainnet also `Type MAINNET to confirm:`.

It then stops the listener and every `grin-wallet` working in that folder, removes the toml, `wallet_data/`, `tor/`, the saved passphrase and seed files and the logs, and deletes the wallet's line from `/opt/grin/conf/grin_wallets_location.conf` so the toolkit backup stops collecting an empty folder (setup adds it back). A **testnet** wallet is deleted. A **mainnet** wallet is **moved** to `/opt/grin/cmdwallet/.retired/mainnet-<date_time>/`, and the screen prints how to put it back (stop the listener, move the contents back into `/opt/grin/cmdwallet/mainnet/`) and how to purge it (`rm -rf` that folder, once you are sure it holds nothing). If a Transporter agent from the [Connectivity Hub](09-connectivity-hub.html#grin-transporter-093) is wired to this wallet, the screen warns that the agent's settings are not changed — re-run the agent's wallet step afterwards. The same warning and the same mainnet move apply to *Re-initialize* in setup step 2.

> **Note:** The listener screen and Nuke were added after the last time this page was checked and are read from the code only; neither has been run on a server.

### Day-to-day operations

| I want to… | Do this |
|------------|---------|
| Restart the listener after a reboot | `A` → `L` → `1) Start` (it asks for the passphrase if none was saved). From a shell: `tmux new -d -s grin_mainnet_cmd_wallet /opt/grin/cmdwallet/mainnet/listen.sh` (only with a saved passphrase). **There is no autostart on reboot and no watchdog for this wallet** — it stays down until you start it |
| Restart a stuck or crashed listener | `A` → `L` → `3) Restart`; `4) Recent output` shows why it stopped |
| Check the balance | `cd /opt/grin/cmdwallet/mainnet && ./grin-wallet info` — see the note above about the listener holding the lock |
| Switch between `listen` and `owner_api` | Re-run `A` → the network → `N` at *Re-initialize?* → pick the mode at step 4b → `y` at *Kill and restart?* (or `L` → `3) Restart` afterwards) |
| Save a passphrase I declined earlier | Stop the listener, re-run the setup on the existing wallet; step 3 asks for the passphrase, verifies it and saves it |
| Update or roll back `grin-wallet` | `B` → the network → `1` install the pinned version · `2` update to upstream latest (read the warning) · `3` roll back to the previous version · `4` pick any cached version · `5` re-verify the installed binary · `6` prune the cache. The screen stops and restarts the listener around a swap |
| Move the wallet to a rebuilt node | Nothing — the `grin-secret-sync` timer re-points `node_api_secret_path` within 5 minutes. To force it: `grin-secret-sync` |
| Start over with a fresh wallet | Re-run the setup and answer `y` to *Re-initialize?*, or use `N` to remove the wallet first and set up later. Testnet is deleted; mainnet is moved to `/opt/grin/cmdwallet/.retired/` after you type `MAINNET`. **Make sure the old seed phrase is written down first** if it ever held funds |

### Troubleshooting

| Symptom | Cause and fix |
|---------|---------------|
| `Port 3415 is held by ANOTHER process` at step 7 (3420 in `owner_api` mode) | Another wallet on this server already listens there. On 3415 that is usually Fidelius's first mainnet wallet; on 3420 / 13420 it is Grin Drop, a solo-mining wallet or the pool wallet, which all run the combined listener. It can also be *this* wallet started by hand outside tmux — `L` shows `grin-wallet running outside tmux` then, and `2) Stop` clears it. The script never kills a foreign holder. Stop that listener, or change `api_listen_port` (or `owner_api_listen_port` for owner_api mode) in `grin-wallet.toml` and re-run |
| `Listener exited immediately` | The saved passphrase does not open the wallet. Run `/opt/grin/cmdwallet/mainnet/listen.sh` in the foreground to see grin-wallet's error; delete `mainnet_pass_wallet.txt` and re-run the setup to save the right one |
| `Session … is alive` but `port … not listening yet` | grin-wallet is still starting (Tor bootstrap can take a minute) — or it failed after the session opened. `tmux attach -t grin_mainnet_cmd_wallet` and read |
| `grin-wallet info failed` — cannot reach the node | The node is not running, or `node_api_secret_path` in the toml points at the wrong file. Check the node ([Script 01](01-build-node.html#after-it-finishes)), then run `grin-secret-sync` |
| `Node secret not found` in the summary | No node from Script 01 on this server. Either build one, or set `check_node_api_http_addr` in the toml to a public node such as `https://api.grin.money` and leave `node_api_secret_path` empty |
| `Could not read the wallet address` | Retry the passphrase; if the wallet was recovered, make sure the phrase was typed correctly (a wrong phrase still "succeeds" — it just opens a different, empty wallet) |
| `Nothing is bound on 3420` after a mode change | You changed the mode and declined the restart. Re-run and answer `y` at *Kill and restart?* |
| `Could not find a 12/24-word phrase` — nothing was written | grin-wallet's output format was not recognised, so no seed file was saved. Copy the phrase from the screen now — it is not stored anywhere else |
| `Listener … holds the wallet` when saving a passphrase | A passphrase cannot be verified while the listener has the wallet open. `L` → `2) Stop`, re-run the setup, then let step 7 start it again |
| `get_version: Cannot parse response` during init | Harmless — see the note in the steps table |
| `Init failed — no …/wallet_data/wallet.seed` or `Recovery did not complete` | grin-wallet wrote its toml but no seed — a passphrase mismatch, a rejected recovery phrase, or a cancelled prompt. Read the output above the message, then re-run the setup: it reports a `Half-initialized wallet`, clears the leftover toml and starts a fresh init. If this happened during a *Re-initialize*, the old wallet was already moved to `/opt/grin/cmdwallet/.retired/` (mainnet) or deleted (testnet) before init ran |
| `Could not stop grin-wallet (PID …) — nothing was removed.` | A re-initialize, Nuke or Stop could not end a `grin-wallet` process working in the wallet folder, even with KILL. Nothing on disk was changed. Check the PID with `ps -p <PID> -o pid,stat,cmd` (a process stuck in state `D` is waiting on the disk), and retry once it has gone |
| A Transporter agent stopped working after a re-initialize or Nuke | Its `agent.json` still points at the old wallet's secret and passphrase files — the screen warned about it. Re-run the agent's wallet step in the [Connectivity Hub](09-connectivity-hub.html#grin-transporter-093) |

## Accio — the public web wallet (not yet run)

> **Warning:** Status — Accio is **written but has never run on any server.** No build, no deployment, no send and no receive has ever been performed on a VPS. Hub key `2` opens its menu and every option there is real code, but none of it has been exercised end to end. Do not put funds through it, and do not offer it to anyone until an acceptance run on testnet has been done. There is no manual page for it until then.

What it is meant to become: a wallet that anyone can open in a browser at your domain, where the seed is generated and kept **in the visitor's browser tab** — the exact opposite of Fidelius, where the server holds the keys. The browser code is a vendored, integrity-checked copy of an MIT-licensed upstream wallet that already supports Grin; the toolkit adds a small Node.js **gateway** (ports 7480 mainnet / 7490 testnet) that forwards the visitor's Tor sends and relays incoming payments to the open tab, an nginx site with HTTPS, an optional `.onion` front, and an offline standalone HTML file that can send but not receive. Its menu today, per network: install/deploy, rebuild the site, gateway service, nginx/SSL/onion, check upstream, build the standalone file, status, uninstall — under a banner that says `NOT YET PROVEN ON A LIVE BOX`. The design and build log are in the toolkit's [script052_design.md](https://github.com/noobvie/Grin-Node-Toolkit/blob/main/docs/reference/script052_design.md) and [script052_implementation.md](https://github.com/noobvie/Grin-Node-Toolkit/blob/main/docs/reference/script052_implementation.md).

## Planned slots

Keys `6` (Payment Pro) and `7` (GoblinPay) are **live keys that install nothing**: each prints one screen naming what the slot is for, says `Nothing was installed or changed`, and returns on Enter. The same goes for the spare slots `4` and `8`. Neither planned product has a script number yet — a number is assigned only on the day a build starts.

## Related

- [Fidelius](051-fidelius.html) — the personal web wallet, and the Grin XP variant
- [Accept GRIN in WooCommerce](053-woocommerce.html) — Script 053, the payments product on this hub
- [Grin Drop](059-grin-drop.html) — Script 059, the giveaway and donation portal
- [Script 01](01-build-node.html) — the node every wallet here talks to
- [Script 04](04-publish-node-api.html) — the public node API, and how a wallet elsewhere points at your node
- [Script 09](09-connectivity-hub.html) — the Connectivity Hub, home of the Transporter an `owner_api`-mode CMD wallet can sit behind
- [Ports and paths](reference-ports-and-paths.html) — the wallet ports and every wallet directory
- [Back up and restore](089-backup-restore.html) — the toolkit-wide backup that includes every wallet directory registered here (and does not restore it automatically — see that page)
