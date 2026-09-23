---
title: Accept GRIN in WooCommerce
description: How Script 053 adds a Grin payment method to WooCommerce — a PHP plugin plus a local Node.js bridge to grin-wallet — and how the invoice flow works.
section: Scripts
order: 5.3
short: WooCommerce
label: Script 053
covers: 2026-09-20
updated: 2026-09-20
---

Script 053 gives a WordPress shop that runs WooCommerce a new payment method: **Grin (GRIN)**. It has two halves. A **PHP plugin** (GrinPay for WooCommerce) lives inside WordPress and shows the buyer an invoice at checkout; a small **Node.js bridge** runs on the same server and talks to a `grin-wallet` on the merchant's behalf. Nothing is exposed to the internet by the script itself — the bridge listens on localhost only, and the shop's existing HTTPS site is the only public surface.

> **Warning:** Status — the wallet hub marks this product 🔧 *building*, and grin.money's toolkit page still lists it as *coming soon*. The plugin, bridge and installer are complete and were security-reviewed in July 2026, but the toolkit's own design document scopes the current phase as *local testnet*, and no public shop is known to run it. Two things you must know before trusting it with an order: **the script does not create the merchant wallet** (see [the merchant wallet](#the-merchant-wallet-you-create-it)), and **a paid order is marked Processing at zero confirmations** (see [the zero-confirmation catch](#the-zero-confirmation-catch)). Rehearse it on **testnet** with a test shop first; on mainnet, treat *Processing* as "payment signed", not "money in the bank", until you have checked your wallet.

## What it does

1. Installs the **bridge** — an Express app copied to `/opt/grin/woocommerce/<network>/` — and two systemd services per network: `grin-woo-bridge-main` / `grin-woo-bridge-test` (the bridge, on `127.0.0.1:3006` for mainnet and `:3007` for testnet) and `grin-woo-wallet-main` / `grin-woo-wallet-test` (a `grin-wallet owner_api` daemon on 3420 / 13420). The bridge translates six plain HTTP calls from the plugin into grin-wallet **Owner API v3** calls, encrypted per call with an ECDH-negotiated key; the session token never touches disk.
2. Copies the **plugin** into `wp-content/plugins/grinpay-woocommerce/` of the WordPress install you name, and writes `bridge-config.php` beside it so the plugin knows which bridge port and network it belongs to. You then activate it in WordPress like any other plugin.
3. Adds to WooCommerce: the payment method, an order status **Pending Grin Payment**, a thank-you page that carries the invoice, a settings page with three tabs (General / System Status / Orders), and a WP-Cron job every 5 minutes that expires unpaid invoices.
4. Optionally packages the plugin as a `.zip` for installing on another WordPress (**minus** `bridge-config.php`, which is server-specific).

Both networks can be installed side by side, each with its own bridge, wallet daemon and port; the plugin's *Network* setting picks which bridge a given shop talks to.

## How a Grin payment works here

Grin has no addresses you can print on an invoice: every payment is a short conversation between two wallets. Script 053 uses Grin's **invoice flow**, which puts the shop in charge of the amount:

1. The shop's wallet creates an **invoice slatepack** for exactly the order total (`issue_invoice_tx`). The amount is baked into it — a buyer cannot pay less by editing the text.
2. The buyer pastes that slatepack into their own wallet, which adds its coins and signs, producing a **response slatepack**.
3. The buyer pastes the response back into the shop page. The shop's wallet finalises the transaction and broadcasts it to the Grin network.

The slatepacks travel by copy-and-paste on purpose. The bridge deliberately leaves the shop's own address out of the invoice, because a buyer wallet with Tor enabled would otherwise deliver its response straight to the shop's wallet, bypassing the page — and the order would never be marked paid.

### The buyer's view

| Step | What the buyer sees | What they do |
|------|--------------------|--------------|
| Checkout | *Grin (GRIN)* as a payment option, with your description text. Only the **block** checkout is supported — the classic shortcode checkout is not | Choose it and place the order |
| Thank-you page, **Step 1 — Copy the Grin Invoice** | The invoice slatepack, a *Copy* button, a *Show QR* toggle, and a countdown (*Invoice expires in* — 30 minutes by default). On testnet a banner says *Testnet mode active* | Copy the slatepack into their wallet. On the command line: save it to a file and run `grin-wallet pay -i invoice.slatepack`, which prints the response. In Grim (the GUI wallet), paste it into the Receive/Send box and confirm the amount |
| **Step 2 — Paste Your Signed Response** | A text box | Paste the response slatepack and click **Submit Payment** |
| Result | *Payment received! Your order is being processed.* and a redirect to the normal order page | Nothing more |

If the buyer closes the tab after Step 1 they can return to the order from *My Account → Orders*; the invoice stays valid until the countdown runs out, after which the order is cancelled and they must place a new one.

### The merchant's view

- **Orders** list: a paid-with-Grin order sits at **Pending Grin Payment** from checkout until the buyer submits the response, then moves to **Processing** with an order note *GrinPay: payment confirmed. TX: … — Amount: … GRIN*. An invoice that runs out is set to **Cancelled** with the note *invoice expired* (by the page's own polling if the buyer still has it open, otherwise by the 5-minute cron).
- **WooCommerce → Settings → Payments → Grin → Orders** tab: every pending Grin order with minutes left, a *View* link and a **Cancel** button.
- **System Status** tab: a live check of PHP (≥ 8.4.1), WordPress (≥ 6.9), WooCommerce (≥ 10.6.1), the block checkout, HPOS, the `curl`/`json` extensions, `bridge-config.php`, and the bridge itself — response time, network and wallet balance, plus the grin node, grin-wallet and Node.js versions the bridge reports. **If any critical check fails, the payment method hides itself at checkout** (*GrinPay is temporarily unavailable*) and a red notice appears on the WooCommerce settings and Plugins pages.
- **General** tab: enable/disable, title and description shown at checkout, connection mode, network, invoice expiry, confirmations, currency mode, debug log, HMAC secret (below).

### The zero-confirmation catch

The moment the buyer's response is finalised, the plugin calls WooCommerce's `payment_complete()` — before the transaction has a single confirmation on chain, and even if the bridge's broadcast to the node failed (it only logs that as a warning and still reports success). The **Confirmations Required** setting (default 1; the settings page recommends 10 on mainnet) is checked only by the background poll and cron, which in practice never see a transaction the submit path has not already completed. This is finding F1 of the toolkit's [security audit](https://github.com/noobvie/Grin-Node-Toolkit/blob/main/docs/generated/script053_security_audit.md), still open. Grin's consensus guarantees the *amount*, so a confirmed payment is always the right one; what can happen is a payment that never confirms (node down at broadcast time, mempool rejection). Until it is fixed, ship valuable goods only after `grin-wallet txs` on the merchant wallet shows the transaction confirmed.

## Before you start

| You need | Notes |
|----------|-------|
| A WordPress site with WooCommerce **on the same server** as the toolkit | The bridge binds `127.0.0.1` and the plugin calls `http://127.0.0.1:3006` or `:3007`. The other connection mode, *GrinPay Server*, targets a hosted service that does not exist yet |
| WordPress ≥ 6.9, WooCommerce ≥ 10.6.1, PHP ≥ 8.4.1 with `curl` and `json` | The plugin refuses to activate below these. Keep the **block checkout** (the default on new stores) and **HPOS** on; pretty permalinks on |
| A synced Grin node | [Script 01](01-build-node.html); the merchant wallet talks to it on 3413 / 13413 |
| `grin-wallet` on the `PATH` | The script only warns if it is missing. The [CMD Wallet quick setup](05-wallet-services.html#the-cmd-wallet-quick-setup) installs a copy per network under `/opt/grin/cmdwallet/`, which is not on the `PATH` — symlink it (below) |
| A merchant wallet, created and funded by you | The next section |
| Node.js 24 | Installed by the script from NodeSource if missing or older |
| `zip` | Only for packaging the plugin (menu 6) |

One `grin-wallet` binary serves both networks, so one link is enough:

```bash
ln -s /opt/grin/cmdwallet/mainnet/grin-wallet /usr/local/bin/grin-wallet
```

## The merchant wallet — you create it

Script 053 does not run `grin-wallet init`. Its wallet service is a bare `grin-wallet [--testnet] owner_api` started as `www-data` with no wallet directory named, so it can only find a wallet in that user's home: `/var/www/.grin/main/` or `/var/www/.grin/test/`. Nothing in the menu creates one there. Two things the bridge needs are set in **3) Configure**:

- **Wallet data dir** — where the bridge reads `.owner_api_secret` to authenticate to the Owner API. Its default, `/opt/grin/woocommerce/<network>/`, is the bridge's own folder and never contains a wallet, so you must point it at the real wallet directory.
- The wallet **passphrase** — the bridge opens the wallet itself (`open_wallet`) using the `GRINPAY_WALLET_PASS` environment variable, which the menu never asks for. Add it with `systemctl edit grin-woo-bridge-main` (or `-test`) as a `[Service]` `Environment=` line; an empty passphrase needs nothing.

The practical route today is to use the [CMD Wallet quick setup](05-wallet-services.html#the-cmd-wallet-quick-setup) from the wallet hub in its **`owner_api` listener mode** — that gives you a wallet in `/opt/grin/cmdwallet/<network>/` already serving the Owner API on 3420 / 13420 with the passphrase fed on stdin, plus its own reboot handling and backup registration. Then in 053 set *owner_api URL* to that port (the default) and *Wallet data dir* to `/opt/grin/cmdwallet/<network>`, start **only the bridge** (`systemctl start grin-woo-bridge-<net>`), and leave 053's own wallet daemon alone — mask it so its `Wants=` dependency does not keep restarting into failure: `systemctl mask grin-woo-wallet-main`. Fund the wallet by sending GRIN to it from another wallet (on testnet, from the faucet at [drop.grin.money](https://drop.grin.money)).

> **Note:** Not verified on a server. The service file runs the bridge as `www-data`, which must be able to *read* the wallet's `.owner_api_secret` (mode 600 by default) — expect to widen that with a group or ACL. The alternative, initialising a wallet as `www-data` in `/var/www/.grin/`, is what the wallet service expects but leaves the seed in the web server's home; the toolkit has no backup entry for it.

## Choices you will make

- **Network.** Testnet is the sane first stop: tGRIN has no value and a test shop can take real orders end to end. Picking mainnet requires typing `MAINNET` at a red confirmation screen; the plugin's own *Network* setting must match the bridge you installed.
- **Currency mode.** *Direct GRIN* means your product prices are already in GRIN. *Auto-convert* divides the order total by a live **USD** rate at checkout — so it is only correct if your store currency is USD. The bridge fetches the rate from Gate.io (its first choice, world.grin.money, returns a shape the bridge does not parse, so it always falls through) and caches it for 15 minutes; if both sources are down it serves the stale value rather than block the checkout.
- **Invoice expiry** (default 30 minutes) and **Confirmations Required** (default 1 — see the catch above).
- **Bridge API key** and **HMAC secret.** Both optional and off by default; the bridge logs a warning at start when they are unset. The HMAC secret signs every POST from the plugin and must be the same value in *3) Configure* (bridge side) and in the plugin's *Security* box (plugin side). Enable it on a server that hosts anything else — it is the only thing stopping another local process from creating invoices.

## The menu

```text
 053) GRIN WOOCOMMERCE

  1) Mainnet  ⚠ real GRIN  wallet● bridge●  (ports 3420/3006)
  2) Testnet  tGRIN — for testing  wallet○ bridge○  (ports 13420/3007)

  0) Back to main menu
```

The two dots after each network are live: `●` means that network's wallet daemon or bridge service is running, `○` that it is not. Pick a network, and the network menu opens with a status block (bridge installed?, plugin installed?, config saved?, wallet daemon and bridge running?) above these options:

```text
  ─── Setup ────────────────────────────────────────
  1) Install bridge        (Node.js + npm + systemd)
  2) Install WP plugin     (copy plugin to WordPress)
  3) Configure             (wallet path, expiry, WP dir)
  4) Start / Stop bridge   (systemd grin-woo-bridge-test)

  ─── Info ─────────────────────────────────────────
  5) Status

  ─── Distribution ─────────────────────────────────
  6) Package plugin        (create distributable .zip)
  7) Pull latest & exit    (git pull origin, then exit)

  ↩  Press Enter to refresh
  0) Back to network select
```

| Key | Action |
|-----|--------|
| `1` | Install Node.js 24 if needed, copy the bridge to `/opt/grin/woocommerce/<network>/`, `npm install`, write both systemd units |
| `2` | Ask for the WordPress root (default `/var/www/html`), copy the plugin into its `wp-content/plugins/`, write `bridge-config.php`, fix ownership to `www-data` |
| `3` | Owner API URL, wallet data dir, API key, HMAC secret, invoice expiry, WordPress root — saved to `bridge.conf` and re-baked into the bridge's unit file (restarting the bridge if it runs) |
| `4` | A sub-menu: start both (wallet daemon first), stop both, restart the bridge only, enable both at boot |
| `5` | Everything at a glance plus a health probe of `/api/status` |
| `6` | Build `web/053_woocommerce/releases/grinpay-woocommerce-v<version>.zip` from the plugin source, without `bridge-config.php` |
| `7` | `git pull` the toolkit and exit so the new files take effect |

## Setup, step by step

The menu numbers its setup keys 1–4 and they work in that order; the design document runs Configure first, which also works because `3` rewrites the unit file whenever it exists.

| Step | What happens | What you do |
|------|--------------|-------------|
| `1` Install bridge | Checks `node` ≥ 24 (installs 24.x from NodeSource otherwise — an existing newer Node is left alone), warns if `grin-wallet` is not on the `PATH`, copies the bridge, runs `npm install --omit=dev`, writes `grin-woo-wallet-<net>.service` and `grin-woo-bridge-<net>.service` and reloads systemd | Wait. Nothing is started yet |
| `2` Install WP plugin | Verifies `<root>/wp-content` exists, copies the plugin (asks *Update plugin files?* if it is already there), generates `bridge-config.php` with the bridge URL, network and expiry, `chown www-data`, saves the root into `bridge.conf` | Enter the WordPress root, or accept `/var/www/html` |
| `3` Configure | Prompts each value with the current one in brackets; secrets are typed blind. Type `none` at the HMAC prompt to clear it | Set **Wallet data dir** to your real wallet directory (see above). Leave the Owner API URL at its default unless the wallet listens elsewhere |
| `4` Start / Stop bridge → `1` | `systemctl start` the wallet daemon, waits 2 s, starts the bridge. Then `4` again to **enable both at boot** | If you use a CMD wallet, skip *Start both* — start the bridge alone from a shell |
| `5` Status | Shows PIDs, ports, paths, the plugin location, and curls `http://127.0.0.1:<port>/api/status` | Look for *Bridge responded on port …* |
| WordPress | *Plugins → GrinPay for WooCommerce → Activate*, then *WooCommerce → Settings → Payments → Grin*: tick **Enable**, set **Network** to the bridge you installed, save. Open the **System Status** tab — every row should be green | If the bridge row is red, the plugin cannot see the bridge: check step 4 |
| Test | On testnet: place an order in your own shop, pay it from a second testnet wallet, confirm the order flips to *Processing* and `grin-wallet txs` on the merchant wallet shows it | Do this before you enable mainnet |

## After it finishes

From a root shell on the server (use `3006` for mainnet):

```bash
curl -s http://127.0.0.1:3007/api/status
```

Good output is JSON with `"success":true`, the network, the grin-wallet and node versions, and a `balance`. Three ways it goes wrong: `"Wallet daemon not reachable"` with HTTP 503 means the bridge is up but nothing answers on the Owner API port; versions of `unknown` mean the Owner API answered but rejected the bridge's credentials — it cannot read `.owner_api_secret` in the wallet dir you configured; versions present but `balance` `null` mean the credentials work and `open_wallet` failed — the passphrase (`GRINPAY_WALLET_PASS`).

```bash
journalctl -u grin-woo-bridge-test -n 30        # bridge log
journalctl -u grin-woo-wallet-test -n 30        # wallet daemon log
```

### What was created

| Path | Purpose |
|------|---------|
| `/opt/grin/woocommerce/<network>/` | The bridge: `server.js`, `lib/wallet-api.js`, `node_modules/` |
| `…/bridge.conf` | Owner API URL, wallet dir, API key, HMAC secret, expiry, WordPress root (mode 600) |
| `…/bridge.log` | Created empty; the bridge itself logs to the journal |
| `/etc/systemd/system/grin-woo-bridge-<net>.service` | The bridge, run as `www-data`, with the values from `bridge.conf` as environment variables |
| `/etc/systemd/system/grin-woo-wallet-<net>.service` | `grin-wallet owner_api` as `www-data` — see the wallet section |
| `<wp-root>/wp-content/plugins/grinpay-woocommerce/` | The plugin |
| `…/grinpay-woocommerce/bridge-config.php` | Bridge URL, network and expiry for this server; never ships in the zip |
| `web/053_woocommerce/releases/*.zip` | Packaged plugins (menu 6), inside the toolkit checkout |
| `/opt/grin/logs/grin_woocommerce_<date>.log` | This run's log |

## Day-to-day operations

| I want to… | Do this |
|------------|---------|
| See pending Grin orders | *WooCommerce → Settings → Payments → Grin → Orders* — cancel one from there if a buyer gives up |
| Check the merchant balance | The *System Status* tab shows it; or `grin-wallet [--testnet] info` on the merchant wallet |
| Change the invoice timeout or confirmations | The plugin's *General* tab. `3) Configure`'s expiry only pre-fills the plugin at first install |
| Turn on request signing | `3) Configure` → HMAC secret, then paste the same secret in the plugin's *Security* box |
| Restart after a config change | `4` → `3) Restart bridge`; `3) Configure` already restarts a running bridge |
| Update the plugin after a toolkit update | `7` (pull), then `2` again and answer `Y` to *Update plugin files?* |
| Ship the plugin to another site | `6`, then *Plugins → Add New → Upload Plugin* over there — and remember that site needs its own bridge |
| Stop taking Grin | Untick **Enable** in the plugin; the bridge can stay running |

## Troubleshooting

| Symptom | Cause and fix |
|---------|---------------|
| System Status: *bridge-config.php not found. Run the Grin Node Toolkit script 053 option 2* | The plugin was installed by hand or from the zip. Run `2` against this WordPress root so the file is generated |
| System Status: *Connection refused (http://127.0.0.1:3007) — … Fix: sudo systemctl start grin-woo-bridge-test* | The bridge is not running, or the plugin's *Network* points at the other port. `4` → start, or fix the setting |
| *GrinPay is temporarily unavailable* at checkout | A critical status check failed and the gateway hid itself. Open the *System Status* tab; the red row says which |
| `/api/status` → `Wallet daemon not reachable` | Nothing listens on the Owner API port. Start the wallet daemon (or your CMD wallet), then retry |
| `balance: null`, invoices fail with *Could not create invoice* | `open_wallet` is failing (wrong or missing `GRINPAY_WALLET_PASS`), or — if the versions read `unknown` too — the bridge cannot read `.owner_api_secret` in the wallet dir you configured. `journalctl -u grin-woo-bridge-<net>` shows the exact error |
| *GrinPay: Finalization failed. Ensure you pasted the correct response slatepack.* | The buyer pasted the invoice back, or a response to a different invoice, or the invoice had expired. Ask them to paste the **response** their wallet produced |
| *GrinPay: Could not fetch Grin exchange rate* | Auto-convert is on and both rate sources failed with no cached value. Switch to Direct GRIN or wait |
| Order stuck at *Pending Grin Payment* although the buyer says they paid | Their wallet signed the invoice but the response was never submitted on the page — nothing has reached your wallet. Until the countdown ends they can reopen the order from *My Account* and paste it; after expiry the order is cancelled and they order again. `grin-wallet txs` on the merchant wallet shows the invoice as unfinalised |
| `Node.js install failed` / `npm install failed` at step 1 | No network to NodeSource/npm, or an old distro. Check `apt-get` works and retry; the bridge needs Node ≥ 24 |
| `WordPress not found at /var/www/html — check the path` | Give the directory that contains `wp-content` — the site root, not the plugins folder |
| `zip failed — is the zip command installed?` at step 6 | `apt-get install zip` |

## Related

- [Wallet & payment services](05-wallet-services.html) — the hub this script is launched from, and the CMD wallet that can serve as the merchant wallet
- [Fidelius](051-fidelius.html) — a browser wallet on the same server; not a merchant wallet for this plugin
- [Script 01](01-build-node.html) — the node the merchant wallet reads the chain from
- [Grin Drop](059-grin-drop.html) — the testnet faucet you can fund a test wallet from
- [Ports and paths](reference-ports-and-paths.html) — every port on the server
- The toolkit's [script053_design.md](https://github.com/noobvie/Grin-Node-Toolkit/blob/main/docs/generated/script053_design.md) and [script053_security_audit.md](https://github.com/noobvie/Grin-Node-Toolkit/blob/main/docs/generated/script053_security_audit.md) for the architecture and the open findings
