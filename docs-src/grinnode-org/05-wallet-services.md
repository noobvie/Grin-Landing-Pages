---
title: Wallet & payment services
description: The wallet hub — what a Grin wallet is, the fixed-slot menu, every wallet and payment product with its status, and the CMD wallet quick setup step by step.
section: Scripts
order: 5
short: CMD wallet
label: Script 05
covers: 2026-11-06
updated: 2026-11-06
---

Main-menu option **5** opens the wallet hub: one screen that shows which wallet and payment products are installed and running on the server, and launches the one you pick. Each product is its own script with its own wallet, ports, nginx site and service. The hub itself installs nothing — except the **CMD Wallet quick setup**, which is built into it and is the fastest way to get a working command-line wallet next to your node.

> **Warning:** Status — the main menu marks this hub **(DEV)**. Two of its products are marked ✅ ready (the CMD wallet and Grin Drop), though the CMD wallet's screens have been rewritten since and have not yet run on a server (see the note in [its section](#the-cmd-wallet-quick-setup)); the rest are marked *building* on the hub screen, and one — Accio — has never run on a server at all (see [Accio](#accio-the-public-web-wallet-not-yet-run) below). Rehearse anything wallet-related on **testnet** first: the toolkit runs both networks side by side precisely so you can.

## A Grin wallet, in plain words

The **node** (from [Script 01](01-build-node.html)) keeps a copy of the chain and talks to other nodes. It holds no coins and no keys. A **wallet** is a separate program — `grin-wallet` — that holds a secret **seed**, derives keys from it, asks a node what is on the chain, and builds transactions. On this toolkit the wallet always talks to a node over the node's Foreign API (port 3413, testnet 13413); it can be your own node on the same server or a public node such as those [Script 04](04-publish-node-api.html) publishes.

Three things about Grin surprise people coming from Bitcoin:

- **There are no addresses on the chain.** Nothing you receive is "sent to an address" that anyone can look up. A Grin wallet does have an address — a **[Slatepack address](reference-glossary.html#slatepack-address)**, `grin1…` on mainnet and `tgrin1…` on testnet — but it is a key for *talking to* the wallet, not a destination on the ledger.
- **Every transaction is a two-way exchange.** The sender's wallet produces a partial transaction (a **[slate](reference-glossary.html#slate-and-slatepack)**), the receiver's wallet signs it and hands it back, and the sender finalises and broadcasts it. Both wallets take part. That exchange can happen automatically when both are online, or by hand: the slate travels as a block of text called a **slatepack** that you copy and paste — in a chat, an email, on paper.
- **Coins that are sent to you need your wallet to answer.** A wallet that is *listening* — running with its Foreign API open, ideally reachable over Tor at its slatepack address — receives without you doing anything. A wallet that is switched off receives nothing until the sender reaches it another way.

The toolkit's wallets move slates three ways: **Tor** (both wallets online; the sender connects to the receiver's address over the [Tor network](reference-glossary.html#tor-and-onion-addresses)), **slatepack** text (copy and paste, either side may be offline), and — for products that support it — the **Transporter**, a store-and-forward queue from the [Connectivity Hub](09-connectivity-hub.html#grin-transporter-093) (main menu 9) so the receiver can be offline at send time.

Two more terms you will meet on every wallet screen. The **[seed phrase](reference-glossary.html#seed-phrase)** — 24 words printed once when the wallet is created — *is* the wallet; anyone holding it holds the coins, and it is the only way to recover them on another machine. The **[passphrase](reference-glossary.html#passphrase)** encrypts the seed file on disk and is asked for every time the wallet is unlocked. The wallet exposes two local APIs of its own: the **Foreign API** (port 3415 / 13415) through which it receives, and the **Owner API** (3420 / 13420) through which it is managed; both stay on localhost and are never opened to the internet.

## What the hub does

1. Probes each product — a config file, app folder or unit file for *installed*; a [systemd unit](reference-glossary.html#systemd-service), a tmux session or, for Grin XP, an nginx site link for *running* — and prints a status line for every one it finds. A fresh server shows `No wallet services installed yet.` WooCommerce never appears in that list, even when installed and running: the hub looks for `grin-wallet-bridge-<net>` units, while Script 053 creates `grin-woo-bridge-<net>` — check it from 053's own menu instead.
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

There is **one wallet per network**. You pick the network first, and that network's screen holds every action, so nothing further asks which network you mean.

> **Note:** This whole flow — the network screens, Add, Renew, Configure, Fix network, Wipe and the listener screen — is read from the code. None of it has been run on a server yet. Rehearse it on testnet before you touch a mainnet wallet.

```text
 05C) GRIN WALLET QUICK SETUP

  A grin-wallet for direct CLI use, testing, or behind the Transporter agent.
  One wallet per network, in /opt/grin/cmdwallet/<net>/, independent of other
  services. The passphrase goes in on stdin, so it never appears in ps.

  MAINNET ○ no wallet
  TESTNET ○ no wallet

  1) Mainnet  (real GRIN)
  2) Testnet  (tGRIN — no monetary value)
  3) Both     (add a wallet to each network that has none)
  0) Back

Select [1-3/0]:
```

| Key | Action |
|-----|--------|
| `1` / `2` | Open [that network's screen](#one-network-s-screen) |
| `3` | Run Add on each network that has no working wallet, mainnet first. A network that already has one is skipped, and cancelling the first stops there without opening the second. If both have one it says `Both networks already have a wallet.` |
| `0` | Back to the hub |

The two status rows change as wallets appear:

| Row | What it means |
|-----|---------------|
| `○ no wallet` | Nothing on this network yet |
| `▲ half-initialized — Add clears it` | An earlier init did not finish: the folder has a toml with no seed, or a seed with no toml. See [Replacing a wallet](#replacing-a-wallet) |
| `▲ wrong network — open it and press F` | The wallet's config does not match this network. See [Fix network](#fix-network-f) |
| `● listening  :3415 · PID 12345 · up 02:14:07  mode listen` | Running and bound to its port |
| `▲ session up, port 13420 not bound …  mode owner_api` | The tmux session is alive but nothing holds the port: still starting, crashed, or you changed the mode and declined the restart |
| `▲ grin-wallet running outside tmux  (PID …)` | The wallet was started by hand; `2) Stop` on the listener screen clears it |
| `○ not running  mode listen` | The wallet is ready and stopped |

### One network's screen

```text
 CMD Wallet · MAINNET

  ⚠  Real GRIN (monetary value)

  Wallet     : initialized
  Listener   : ● listening  :3415 · PID 12345 · up 02:14:07
  Mode       : listen — Foreign API 3415
  Passphrase : saved — starts unattended
  Folder     : /opt/grin/cmdwallet/mainnet

  ─── Run ──────────────────────────────────────────────
  1) Listener   start · stop · restart · recent output
  2) Configure  listener mode, node secret, ports, logging — wallet untouched

  ─── Wallet ───────────────────────────────────────────
  3) Add        — this network already has one; Renew replaces it
  4) Renew      replace it: new seed, or recover from a phrase
  5) Wipe       stop and archive to .retired/

  B) grin-wallet binary  install · update · roll back · verify
  0) Back

Select [1-5/B/0]:
```

The keys never move. A row that does not apply right now prints dimmed with the reason, and pressing its key only repeats that reason. On testnet there is no warning line and row `5` reads `stop and delete`.

| Key | Action |
|-----|--------|
| `1` Listener | [The listener screen](#the-listener-screen) — start, stop or restart without walking through setup. Needs a finished wallet |
| `2` Configure | Keeps the wallet and runs [setup](#setup-step-by-step) from the config steps on: listener mode, toml, checks, listener. Use it to switch modes, to save a passphrase you declined, or to finish a setup you cancelled. Needs a finished wallet on the right network |
| `3` Add | Creates or recovers a wallet on a network that has none, or that is half-initialized |
| `4` Renew | [Replaces](#replacing-a-wallet) this network's wallet with a new or recovered one. The old wallet is moved (mainnet) or deleted (testnet) |
| `5` Wipe | [Removes](#wipe-start-a-network-over) this network's wallet and leaves the network empty |
| `B` | The `grin-wallet` binary screen for this network: install, update, roll back, verify |
| `F` | [Fix network](#fix-network-f). Appears only when the check below the status block fails, and the prompt then reads `Select [F/1-5/B/0]` |
| `0` | Back to the overview |

### The two listener modes

Every network's wallet runs in one of two modes, chosen during setup and remembered in `.listen_mode`:

| Mode | Port | What it can do | Tor |
|------|------|----------------|-----|
| **`listen`** (default) — `grin-wallet listen` | Foreign API on **3415** / 13415 | **Receive only.** Other wallets can pay you; nothing can drive a *send* through this process | grin-wallet starts its own Tor for the listener, so the wallet is reachable at its `grin1…` address over Tor with nothing else to configure |
| **`owner_api`** — `grin-wallet owner_api` | Owner + Foreign API together on **3420** / 13420 | Receive **and** send, driven over HTTP. Required by anything that operates the wallet programmatically — the Transporter agent from the Connectivity Hub (main menu 9) cannot send through `listen` at all | **No automatic Tor listener** in this mode |

Pick `listen` unless something needs to send *through* the wallet for you. You can switch later with `2) Configure`, which leaves the wallet itself alone.

> **Note:** Which Tor `listen` uses depends on the wallet's `grin-wallet.toml`. A wallet created by v5.5.0 gets `use_integrated = true` under `[tor]`, so grin-wallet runs a Tor client built into itself (Arti); a toml written by an older release has no such key and keeps launching the system `tor` binary, which must then be installed. Either way the onion address comes from the wallet seed. This is read from the toolkit's notes on the upstream release, not observed on a server.

### Setup, step by step

Add, Renew and Configure are one flow, so the config steps can never differ between them. The banner names the action (`CMD Wallet — Add wallet · MAINNET`) and the script shows the target — network, node port, current listener mode, the wallet directory, the binary, the passphrase and seed file paths, the tmux session name — then runs the steps below. Configure skips step 2, and step 4 only follows a new wallet. Every toolkit prompt in these steps accepts `0` to cancel or skip; grin-wallet's own recovery prompts in step 2 do not.

| Step | What happens | What you do |
|------|--------------|-------------|
| 1 | **Binary.** Only if the wallet folder has none: downloads the pinned `grin-wallet` release (**v5.5.0**) from GitHub into the shared version store `/opt/grin/wallet-bin/<tag>/` and copies it to `/opt/grin/cmdwallet/<network>/grin-wallet`. The download is checked against the release's SHA256 when the release publishes one: a mismatch stops the install, and with no checksum to compare it warns `the binary is unverified` and installs anyway. If a binary is already there it prints `Binary already installed` and moves on; changing versions is the job of `B` | Nothing |
| 2 | **Init or recover** (Add and Renew). `1) New wallet` or `2) Recover from seed`. **New:** you type a passphrase twice (hidden), `grin-wallet init -h` runs with it on stdin, and grin-wallet prints the **24-word seed phrase**. **Recover:** the screen warns that the next prompts are grin-wallet's own, then asks `Is your recovery phrase ready? [y/N/0 cancel]`. `grin-wallet init -hr` then asks on the terminal for the **recovery phrase first, then a new password**. The phrase prompt shows what you type, so a passphrase typed there by mistake stays on the screen. The phrase goes straight into grin-wallet and through no toolkit file. Either way, success is judged by `wallet_data/wallet.seed` appearing. On Renew the old wallet is retired just before init runs — see [Replacing a wallet](#replacing-a-wallet) | **Write the seed phrase down** — it is shown once |
| 3 | **Save the passphrase?** Default **yes**, to `<network>_pass_wallet.txt`, root-only (mode 600). Without it the listener asks for the passphrase at every start and cannot come back unattended after a crash. New wallet: `Save passphrase to <network>_pass_wallet.txt? [Y/n/0 cancel]`. After a recovery, or on Configure with no saved copy: `Save the passphrase for unattended listener start? [Y/n/0 skip]`, then you type it and the script **verifies it opens the wallet** before writing it (`0` or Enter skips). On Configure with a saved copy this step is skipped, and a running listener blocks it, because a passphrase cannot be verified while the listener holds the wallet | Enter, or `n` if you prefer to type it at every start |
| 4 | **Save the seed phrase?** `[y/N/0 cancel]`, new wallets only, default **no**. A plaintext mnemonic beside the wallet it unlocks defeats the passphrase; say yes only if you know why you want a copy at `<network>_seed.txt` (mode 600). After a recovery it says the seed was not saved because you already hold the phrase | Enter |
| 4b | **Listener mode.** `1) listen` or `2) owner_api` at `Select [1/2/0 cancel, Enter = keep <mode>]`. A running listener in the old mode is restarted on the new port at step 7 | Pick — see the table above |
| 5 | **Config.** Patches `grin-wallet.toml`: `node_api_secret_path` → the live node's `.foreign_api_secret`; `api_listen_port` = 3415 / 13415 and `owner_api_listen_port` = 3420 / 13420 (grin-wallet writes mainnet ports even for testnet, so both are pinned every time); `owner_api_include_foreign = true` for owner_api mode; `log_max_files = 10`, and `file_log_level` and `stdout_log_level` both `Debug`, so a failed send or receive can be read from the log or the tmux pane. If `check_node_api_http_addr` names a **remote** node the secret is not written, because grin-wallet sends it to whichever node the toml names. Registers the directory in `/opt/grin/conf/grin_wallets_location.conf` so **Admin & Maintenance → Backup** includes it, and installs the 5-minute `grin-secret-sync` timer that re-points the wallet at the node after a node rebuild | Nothing |
| 6 | **Checks.** `grin-wallet address` (a local operation — proves the passphrase), then `grin-wallet info` (refreshes against the node — the only step that proves the **wallet → node link** works; capped at 90 s). Skipped if a listener already holds the wallet, or if the script does not know the passphrase (you skipped it in step 3) | Read the result |
| 7 | **Listener.** Refuses if the binary or toml is missing, if this wallet is already running outside tmux, if the network check fails, or if another process holds the port (it never kills it — it may be a wallet with funds). With no saved passphrase it asks for one (`0` skips the start). If this wallet's session already exists: `Kill and restart? [y/N/0 skip]`. Writes `listen.sh`, starts it in the tmux session `grin_<network>_cmd_wallet`, waits up to 15 s for the port | `y` to restart after a mode change |
| — | **Summary.** Ten rows numbered 1–9 plus 5b (binary, init, passphrase, seed, node secret, mode, ports, checks, listener, backup registration), the wallet address, quick-reference commands, and a pointer to `1) Listener` for later restarts | Read it |

> **Note:** During `init` grin-wallet may print `get_version: Cannot parse response`. That is **harmless**: init runs before step 5 gives the wallet the node's secret, so its version probe fails, but the seed is written all the same. Only `info` in step 6 tells you whether the wallet can really reach the node.

**Cancelling after init.** Once a wallet has been created, a `0` at `Save passphrase`, `Save seed phrase` or the mode prompt prints `The wallet was created, so it stays.` The wallet exists, but its toml is not patched, no listener runs and **backups do not include it yet**. The screen waits for Enter, so a printed seed phrase stays visible: write it down, then run `2) Configure` to finish.

### Replacing a wallet

Renew asks all its questions before it touches the old wallet. In order:

1. `Replace it? (the new wallet takes over this network) [y/N/0 cancel]`. Anything but `y` prints `Nothing was changed.`
2. `1) New wallet` or `2) Recover from seed`, then the new passphrase, or `Is your recovery phrase ready?`
3. A warning if a Transporter agent is wired to this wallet. On **mainnet**, `Type MAINNET to confirm (0 cancel):`, in exact capitals.
4. The old wallet is retired. Its listener and every `grin-wallet` working in the folder are stopped. A **mainnet** wallet is *moved* to `/opt/grin/cmdwallet/.retired/mainnet-<date_time>/`; a **testnet** wallet is **deleted**. The binary, its version record and `.listen_mode` stay in place.
5. `grin-wallet init -h` or `init -hr` runs.

A `0` before step 4 leaves the wallet as it was.

> **Danger:** Step 4 happens **before** the new wallet exists, and nothing puts the old one back for you. If init then fails, or grin-wallet rejects your recovery phrase, the network has no working wallet: a testnet wallet's files are gone and only its seed phrase can rebuild it, and a mainnet wallet exists only in `.retired/`. Cancelling at a later prompt does not bring it back either. Before you Renew anything that ever held funds, make sure you hold the old wallet's seed phrase, and have the recovery phrase in front of you if you chose to recover.

> **Danger:** To go back on mainnet after a failed Renew, use the folder Renew printed as `Old wallet moved →`, the one with `wallet_data/` inside. If the network reads `half-initialized`, first run `5) Wipe` (keep the binary) to clear the leftovers. Wipe moves them to a **second, newer** folder in `.retired/`, and the `Restore:` and `Purge:` lines it prints name that new folder, which holds no wallet. Do not restore from it. Stop the listener if one is running, move the contents of the **older** folder back into `/opt/grin/cmdwallet/mainnet/`, hidden files included, then run `2) Configure`. That registers the wallet for backup again and asks for the listener mode, which Wipe reset to `listen`.

Add on a **half-initialized** network clears the leftovers first. A folder with a `grin-wallet.toml` but no `wallet_data/wallet.seed` holds no seed, so the script says `Half-initialized wallet` and clears it with no `Replace it?` and no `MAINNET` question (on mainnet it is moved to `.retired/` too, on testnet deleted). A folder with a **seed but no toml** is different: Add then asks both of those questions, exactly as Renew does, because a seed is there.

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

> **Note:** The script's own comments say a running listener holds the wallet database lock, so a second `grin-wallet` command in the same directory may block until it times out. If `info` hangs, stop the listener first (`1) Listener` → `2) Stop`), run the command, then start it again (`1) Start`). This was taken from the code, not observed on a server.

#### What was created

| Path | Purpose |
|------|---------|
| `/opt/grin/cmdwallet/<network>/grin-wallet` | The wallet binary, a copy of `/opt/grin/wallet-bin/<tag>/grin-wallet` |
| `…/grin-wallet.toml` | Wallet configuration, patched in step 5 |
| `…/grin-wallet.toml.before-network-fix-<date_time>` | Only after [Fix network](#fix-network-f): the toml as it was before the fix |
| `…/wallet_data/wallet.seed` | The encrypted seed — the file that *is* your wallet. Back it up (**[Admin & Maintenance → Backup](089-backup-restore.html)** does — but its restore menu does not put this directory back; that page shows the manual step) |
| `…/<network>_pass_wallet.txt` | The saved passphrase (if you agreed), mode 600 |
| `…/<network>_seed.txt` | The plaintext seed phrase (only if you asked for it), mode 600 |
| `…/.init_capture` | Exists only while a new wallet is being created, and holds the printed seed phrase (mode 600). If setup is killed outright it can stay behind; opening the network's screen deletes it |
| `…/.listen_mode` | `listen` or `owner_api` |
| `…/listen.sh` | The generated launcher the tmux session runs; it feeds the passphrase on stdin, never on the command line |
| `…/.grin-wallet.version` | Which binary version is installed and which one to roll back to |
| `/opt/grin/wallet-bin/<tag>/` | The shared binary store used by every wallet product on the box. A version is checksum-checked only if its release publishes a checksum (step 1) |
| `/opt/grin/conf/grin_wallets_location.conf` | `CMDWALLET_<NETWORK>_WALLET_DIR="…"` — how the backup script finds the wallet |
| tmux session `grin_<network>_cmd_wallet` | The listener. It lives on **root's** tmux server (plain `tmux ls`), unlike the node sessions, which are on the `grin` user's (`gtmux ls`) |
| `/opt/grin/cmdwallet/.retired/mainnet-<date_time>/` | Only after a mainnet Renew, a half-initialized clean-up or a Wipe: the old wallet, moved here (mode 700) instead of deleted, with its saved passphrase and seed files if it had them. Not registered for backup, and a full cleanup deletes it with the rest of `/opt/grin` — copy it off the server or purge it yourself |

### The listener screen

`1) Listener` on a network's screen opens a small screen for that network's listener. It changes no configuration — mode, ports and the toml stay Configure's job — and uses the same start and stop code as setup:

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
| `1` | Starts the listener: the saved passphrase if there is one (otherwise it asks), the same guards as setup step 7, the same `listen.sh` launcher. If the session is already up it says so and points you at `3) Restart` |
| `2` | Stops the tmux session **and** every `grin-wallet` process whose working directory is this wallet's folder — including one you started by hand outside tmux. It waits up to 10 s, then sends TERM, then KILL. It never touches a process that merely holds the port from somewhere else |
| `3` | Stop, then Start. Because Stop waits for the wallet's own processes to exit, the new listener never fights the old one for the wallet's database lock. On a wallet that fails the network check it refuses before stopping anything |
| `4` | The last 25 lines of the wallet's log file and the last 15 lines of its tmux pane, plus the commands to follow them live. In a live `tmux attach`, detach with Ctrl+B then D — **Ctrl+C stops the listener** |

The status line also catches a wallet that was started by hand (for example by running `listen.sh` in the foreground): `▲ grin-wallet running outside tmux`. `2) Stop` clears it.

### Fix network (F)

grin-wallet takes its chain from `chain_type` in the toml whenever a toml exists; `--testnet` only decides what a *new* toml gets. So a testnet toml sitting in the mainnet folder runs as testnet, with ports that make it look like mainnet, and hands out an address nobody on mainnet can pay. The toolkit reads the toml (no passphrase needed) and flags three things: a `chain_type` that does not match the folder's network, a **local** node address on the wrong port, and wallet data kept outside the wallet folder. A remote node address is not checked, because its port says nothing about its network.

When one of these is true, the overview row says `▲ wrong network`, and the network's screen shows `▲ This wallet is on the wrong network`, each problem, and `F) Fix network  correct the toml — seed and keys unchanged`. Until it is fixed, `2) Configure`, Start and Restart all refuse. Stop, Renew, Wipe and `B` still work.

`F` lists what it will change, warns if a Transporter agent is wired to this wallet, and asks `Fix the <network> wallet? [y/N/0 cancel]`. On `y` it:

1. Stops this wallet's listener.
2. Keeps a copy of the toml as `grin-wallet.toml.before-network-fix-<date_time>`.
3. Sets `chain_type`, both listen ports, the local node address and the live node's secret, on a copy that replaces the toml only if every edit took. A remote node is left as it is and gets no local secret.

The seed and keys do not change. The address keeps its key and takes the right network's prefix. **The listener is left stopped on purpose**, because what the wallet recorded on the other chain stays until you clear it. Run this first (it asks for the passphrase), then start it from `1) Listener`:

```bash
cd /opt/grin/cmdwallet/<network> && ./grin-wallet scan -d
```

If the wallet data is outside the folder, `F` refuses with `Not repaired: this toml runs on the wallet data in <dir>.`, because correcting the network here would not change which wallet is in use. Set `data_file_dir` in the toml by hand, or Renew to start clean; Renew does not touch data kept outside the wallet folder.

### Wipe: start a network over

`5) Wipe` removes this network's CMD wallet and leaves the network empty — useful when testing. It shows what it found (whether a seed exists, whether the listener runs, whether a saved seed copy is on the box; on mainnet with no saved copy it reminds you to hold the phrase), and collects every answer before it touches anything:

1. `Keep the grin-wallet binary, so Add skips the download? [Y/n/0 cancel]`, asked only when a binary is there. `Y` keeps the binary and its version record; `n` takes the whole folder.
2. `Wipe the <network> CMD wallet? [y/N/0 cancel]`, and on mainnet also `Type MAINNET to confirm (0 cancel):`.

It then stops the listener and every `grin-wallet` working in that folder, removes everything else in the folder — the toml, `wallet_data/`, `tor/`, the saved passphrase and seed files, the logs, `listen.sh` and `.listen_mode`, so the next Add starts from mode `listen` — and deletes the wallet's line from `/opt/grin/conf/grin_wallets_location.conf` so the toolkit backup stops collecting an empty folder (Add puts it back). A **testnet** wallet is deleted. A **mainnet** wallet is **moved** to `/opt/grin/cmdwallet/.retired/mainnet-<date_time>/`, and the screen prints how to put it back (stop the listener, move the contents back into `/opt/grin/cmdwallet/mainnet/`, hidden files included; if you answered `n` above, create that folder first) and how to purge it (`rm -rf` that folder, once you are sure it holds nothing). After a move back, `2) Configure` registers the wallet for backup again. If a Transporter agent from the [Connectivity Hub](09-connectivity-hub.html#grin-transporter-093) is wired to this wallet, the screen warns that the agent's settings are not changed — re-run the agent's wallet step afterwards. Renew gives the same warning and makes the same mainnet move.

### Day-to-day operations

| I want to… | Do this |
|------------|---------|
| Restart the listener after a reboot | `A` → the network → `1) Listener` → `1) Start` (it asks for the passphrase if none was saved). From a shell: `tmux new -d -s grin_mainnet_cmd_wallet /opt/grin/cmdwallet/mainnet/listen.sh` (only with a saved passphrase). **There is no autostart on reboot and no watchdog for this wallet** — it stays down until you start it |
| Restart a stuck or crashed listener | `A` → the network → `1) Listener` → `3) Restart`; `4) Recent output` shows why it stopped |
| Check the balance | `cd /opt/grin/cmdwallet/mainnet && ./grin-wallet info` — see the note above about the listener holding the lock |
| Switch between `listen` and `owner_api` | `A` → the network → `2) Configure` → pick the mode at step 4b → `y` at *Kill and restart?* (or `1) Listener` → `3) Restart` afterwards) |
| Save a passphrase I declined earlier | Stop the listener, then `2) Configure`; step 3 asks for the passphrase, verifies it and saves it |
| Update or roll back `grin-wallet` | `A` → the network → `B` → `1` install the pinned version · `2` update to upstream latest (read the warning; you type the tag to confirm) · `3` roll back to the previous version · `4` pick any cached version · `5` re-verify the installed binary · `6` prune the cache. If a listener is still running the old binary after a swap, the screen asks `Restart the listener now? [y/N]`; `N` leaves it on the old binary until its next restart. That restart only ends the tmux session, so a wallet started by hand outside tmux needs `1) Listener` → `2) Stop` first |
| Move the wallet to a rebuilt node | Nothing, on a wallet that uses the local node — the `grin-secret-sync` timer re-points `node_api_secret_path` within 5 minutes, and a running listener picks it up at its next start. To force it: `grin-secret-sync`. `2) Configure` does the same re-point |
| Start over with a fresh wallet | `4) Renew` to replace it in one go, or `5) Wipe` to remove it and `3) Add` later. Testnet is deleted; mainnet is moved to `/opt/grin/cmdwallet/.retired/` after you type `MAINNET`. **Make sure the old seed phrase is written down first** if it ever held funds |

### Troubleshooting

| Symptom | Cause and fix |
|---------|---------------|
| `Port 3415 is held by ANOTHER process` at step 7 (3420 in `owner_api` mode) | Another wallet on this server already listens there. On 3415 that is usually Fidelius's first mainnet wallet; on 3420 / 13420 it is Grin Drop, a solo-mining wallet or the pool wallet, which all run the combined listener. The script never kills a foreign holder: stop that listener, then use `1) Listener` → `1) Start`. The message also suggests changing the port in `grin-wallet.toml`, but that does not get you past it: the check looks at the network's fixed port, and Configure pins the toml back to it |
| `grin-wallet is already running in` the wallet folder `outside tmux` | This wallet was started by hand. `1) Listener` → `2) Stop` clears it, then Start |
| `Not started — this <network> wallet is configured for the wrong network:` | The toml does not match the folder's network; the lines below it say how. Press `F` on the network's screen — see [Fix network](#fix-network-f) |
| `Wrong network:` an address `is not a <network> address. Do not hand it out.` | The address read at step 6 has the other network's prefix, and the summary still prints it. Do not give it to anyone. `F` on the network's screen corrects it |
| `Not repaired: this toml runs on the wallet data in` another folder | Fix network will not repair a toml whose data lives outside the wallet folder. Set `data_file_dir` by hand, or Renew |
| `Listener exited immediately` | Usually the saved passphrase does not open the wallet. Run `/opt/grin/cmdwallet/mainnet/listen.sh` in the foreground to see grin-wallet's error; delete `mainnet_pass_wallet.txt` and run `2) Configure` to save the right one |
| `Session … is alive` but `port … not listening yet` | grin-wallet is still starting (Tor bootstrap can take a minute) — or it failed after the session opened. `tmux attach -t grin_mainnet_cmd_wallet` and read |
| `grin-wallet info failed` — cannot reach the node | The node is not running, or `node_api_secret_path` in the toml points at the wrong file. Check the node ([Script 01](01-build-node.html#after-it-finishes)), then run `grin-secret-sync` |
| `Node secret not found` in the summary | No node from Script 01 on this server. Either build one, or set `check_node_api_http_addr` in the toml to a public node such as `https://api.grin.money` and leave `node_api_secret_path` empty, so no local secret goes to that host. Configure and the `grin-secret-sync` timer both leave a remote-node wallet's secret alone, and the summary then reads `skipped — wallet uses a remote node` |
| `Could not read the wallet address` | The passphrase did not open the wallet, or the wallet is damaged. If a wrong passphrase was saved, delete `<network>_pass_wallet.txt` and run `2) Configure`; if the wallet was recovered, make sure the phrase was typed correctly (a wrong phrase still "succeeds" — it just opens a different, empty wallet) |
| `Nothing is bound on 3420` after a mode change | You changed the mode and declined the restart. `1) Listener` → `3) Restart` |
| `Could not find a 12/24-word phrase` — nothing was written | grin-wallet's output format was not recognised, so no seed file was saved. Copy the phrase from the screen now — it is not stored anywhere else |
| `Listener … holds the wallet` when saving a passphrase | A passphrase cannot be verified while the listener has the wallet open. `1) Listener` → `2) Stop`, run `2) Configure`, then let step 7 start it again |
| `get_version: Cannot parse response` during init | Harmless — see the note below the steps table |
| `Init failed — no …/wallet_data/wallet.seed` or `Recovery did not complete` | grin-wallet wrote its toml but no seed — a passphrase mismatch, a rejected recovery phrase, or a cancelled prompt. Read the output above the message. The network now reads `half-initialized`, and `3) Add` clears the leftover toml and starts a fresh init. If this happened during a Renew, the old wallet was already moved to `/opt/grin/cmdwallet/.retired/` (mainnet) or deleted (testnet) before init ran — see [Replacing a wallet](#replacing-a-wallet) |
| `Could not stop grin-wallet (PID …) — nothing was removed.` | A Renew, Wipe, Fix network or Stop could not end a `grin-wallet` process working in the wallet folder, even with KILL. Nothing on disk was changed. Check the PID with `ps -p <PID> -o pid,stat,cmd` (a process stuck in state `D` is waiting on the disk), and retry once it has gone |
| A Transporter agent stopped working after a Renew or Wipe | Its `agent.json` still points at the old wallet's secret and passphrase files — the screen warned about it. Re-run the agent's wallet step in the [Connectivity Hub](09-connectivity-hub.html#grin-transporter-093) |

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
