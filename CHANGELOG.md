# Changelog

## 0.14.0
- New **Findings** tab (⌘5): findings with severity, **CVSS 3.1 calculator** (base + temporal metrics, vector in/out, severity follows the score), affected hosts/services, description/impact/evidence/recommendation/references, status and source. Created by hand (+, ⌘N), from a Targets node (**Finding** button: notes → evidence, host:port → affected), from a knowledge-base record (**Create finding**, columns mapped by name) or from scanner imports. Markdown and HTML **report export** with a summary table; Word opens the HTML.
- **Engagements**: targets, notes, findings, the log and evidence screenshots are now kept per engagement (briefcase menu in the top bar; existing data moves into "Default engagement" automatically). Each engagement has client/reference/period/notes and a **scope** (CIDR, IP, range, hostname/wildcard, IPv6 prefix) with exclusions, an in-scope checker, orange shields on out-of-scope hosts in Targets and a warning in the import summary.
- **Import scan** now reads **Nessus** (.nessus), **nuclei** (JSON/JSONL/-je) and **masscan** (-oL, -oJ, -oG) besides nmap; the format is detected. Scanner findings become nodes under the port (from a chosen severity) and, optionally, entries in Findings (one per plugin/template with all affected host:ports, merged on re-import). Large files are imported directly.
- ⌘K knows findings and engagements; evidence screenshots can be linked into a finding; Tools menu gets New Finding (⌘N) and Manage Engagements.
- Tabs are now ⌘1 … ⌘9 (Findings sits after Targets).

## 0.13.1
- **Identify hash** rebuilt: 130+ formats (Unix crypt family, PBKDF2/scrypt/Argon2 notations, Windows/AD incl. NetNTLMv1/v2, pwdump lines, Kerberos etypes 17/18/23, DCC2, DPAPI, BitLocker; databases; LDAP/AIX; Django/phpass/Drupal/WordPress; Cisco/Juniper/FortiGate; Office/PDF/archives/wallets/keys; JWT), *likely* vs *less likely* candidates, a ready-made hashcat/john command line, and it now looks through what surrounds a hash: labels (Responder output), `user:hash` and /etc/shadow lines, `hash:salt` with salt-length hints, `0x` prefixes, checksum lines, colon-separated fingerprints, Cisco configuration lines and hashes inside longer text.
- Empty-password NTLM, disabled-LM and empty-string MD5/SHA digests are pointed out instead of just named.
- New Chef operations **Cisco type 7 decode/encode** and **Juniper $9$ decode**; the magic bar suggests them.

## 0.13.0
- **⌘K Search everything**: notes, one-liners, targets, knowledge base, Exploit-DB, Chef operations, log and actions in one box.
- **Evidence screenshots** (⌘⇧E): macOS screencapture, timestamped file in the evidence folder, Markdown link in the selected target node, Log entry; camera buttons in Targets and Log.
- **Identify hash** in Chef (with hashcat mode / john format) plus a magic suggestion.
- **Connections** menu in the terminal: saved ssh/jump-host commands that open in a new tab.
- **Find in terminal** (⌘F, ⌘G, ⌘⇧G) through SwiftTerm's find bar.
- **Update check** against the GitHub releases (Settings › Tools, and once a day at launch); the version now lives in `AppInfo.version` and build.sh reads it.

## 0.12.1
- Fix: selecting a port made the Targets detail pane shrink and centre oddly (the suggestions panel's text widths drove the old HSplitView). Targets now uses the same fixed-fraction, draggable split as the Knowledge base (default 42% tree / 58% detail, double-click the divider to reset).

## 0.12.0
- **Suggestions at port nodes**: the product/version from the nmap service description is searched in Exploit-DB (version-aware) and in the knowledge base; hits are shown under the port with one-click navigation.
- **Service-aware templates**: ports get a checklist for their service (HTTP, SSH, FTP, SMB, RDP, DNS, LDAP, Kerberos, MSSQL, MySQL, PostgreSQL, SMTP, POP3/IMAP, SNMP, Telnet, VNC, NFS, RPC, WinRM, Redis, MongoDB, Elasticsearch, Docker); editable under Settings › Targets.
- New **Log** tab (⌘8): timestamped activity log of pasted commands, typed commands (skipped while echo is off), imports, actions and your own notes; Markdown export per day.
- **$LHOST / $LPORT** next to $RHOST in One-liners, with detection of your VPN address; export sets all three.

## 0.11.0
- New **Chef** tab (⌘7): CyberChef-style recipes. 60+ operations: Base64/Base32/hex/binary/URL/HTML/Unicode/char codes, ROT13/Caesar/XOR, JWT decode, MD5/SHA-1/SHA-256/SHA-384/SHA-512/CRC-32/HMAC, text tools (case, sort, unique, count, regex find/replace and extract), JSON beautify/minify, gzip/zlib, hexdump, extractors (IPv4, URLs, emails, domains, hashes, CVEs, strings), defang/fang, IPv4 ↔ integer, CIDR calculator, URL parser, Unix timestamps. Auto-bake, magic detector, saved recipes.

## 0.10.0
- New **Searchsploit** tab (⌘6): Exploit-DB search built in. Downloads the official `files_exploits.csv` (or imports a local searchsploit copy), searches offline with version-aware matching (exact, ranges like `< 2.4.50`, families like `2.4.x`), filters on platform/type/verified/DoS, and shows copy-and-paste command lines per exploit (searchsploit -m/-x/-p, Kali path, wget/curl downloads, run/compile hint, serve to another machine).

## 0.9.0
- New **Knowledge base** tab (⌘5): import a findings sheet (.xlsx, .csv/.tsv or .json) and search every column of every sheet; filters for scope and severity, highlighted matches, clickable links, copy as Markdown and "Add to target" (appends the finding to the selected Targets node).
- Filter on kill chain phase (ATT&CK tactic order) next to scope and severity; the phase is shown in the result list.
- The list/detail divider in the Knowledge base starts at two thirds of the width, can be dragged (double-click resets) and remembers its position.
- The .xlsx importer has no dependencies (unzip + XMLParser); the imported data stays local in Application Support.

## 0.8.0
- Everything translated to English: UI, menus, default one-liners and templates, build script, docs and code comments.
- One-time migration of stored data: Dutch default snippet titles/categories and template node names become English; your own notes and text are untouched.

## 0.7.0
- One-liners use `$RHOST` (or `${RHOST}`) as the placeholder; `<ip>`, `<target>` and `$TARGET` keep working.
- **export** button next to the target field runs `export RHOST=…` in the active terminal tab.
- Existing one-liners containing `<ip>` are converted once.

## 0.6.0
- ⌘Esc is the default hotkey (a stored F12 default is replaced once).

## 0.5.0
- Adjustable corner radius, optionally for the top corners too; rounding now happens at the AppKit level so the terminal joins in.
- Adjustable animation duration (0 = instant).
- Settings split into tabs: General, Appearance, Terminal, Targets.

## 0.4.0
- Panel-wide transparency, blur on/off and an extra layer under the terminal text.
- Fix: the terminal background ignored the configured opacity.

## 0.3.0
- Hotkey freely configurable through a recorder field (any key or combination), with a check whether macOS accepts the combination.

## 0.2.0
- Focus is handed back through cooperative activation after hiding; fixes "mouse works, keyboard doesn't" in remote desktops.
- **Pause hotkey in** setting for apps such as Windows App / Remote Desktop / Parallels.

## 0.1.0
- First version: drop-down panel with terminal (SwiftTerm), notes, one-liners with copy button and a targets tree with nmap import (normal, -oG, -oX).
