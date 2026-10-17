# Changelog

## 0.28.1
- Annotator: marks landed at the bottom of the image instead of where you dragged — the drag gesture now uses one named coordinate space for the whole canvas area.

## 0.28.0
- **Screenshot annotation in Findings**: images linked under Evidence show as thumbnails; click one to draw arrows, boxes, circles, text labels and highlights, and to **blur** (pixelate) or **redact** (solid black) credentials, hashes and names before a screenshot goes into the report. Colours, three line widths, drag to move, undo / redo, ⌘⌫ to remove a mark. Marks are rendered into the pixels at full resolution — a blurred or redacted area is not recoverable from the saved file. Saves as `<name>-annotated.png` next to the original and relinks the evidence (or **Replace original**); **Add image…** links existing screenshots; thumbnail context menu with Show in Finder, Copy path, Remove link. Saves are written to the Log.

## 0.27.0
- **Balanced top bar**: Knowledge base, Searchsploit, Chef and Diagram moved into the Tools tab's sidebar by default (once; your own layout is kept afterwards), leaving Terminal, Notes, One-liners, Targets, Findings, Plan, Log and Tools in the top bar. Right-click a tab › **Move into Tools**, right-click a tool › **Give it a tab in the top bar**; tools can be reordered by dragging; **Reset tabs and tools** in the context menus, View menu and Settings › Appearance. The View menu lists the tools below the tabs; ⌘K "Go to" covers both. Every module still stays mounted wherever it lives.

## 0.26.0
- **Tools › Reachability canary**: probe in-scope hosts every 1–60 minutes (TCP connect to a port, or ICMP via `ping`), picked from Targets or entered by hand; badge in the top bar (green / red with the number of unreachable targets; click opens the tool), latency, last check, last change and a strip of recent results per target; a change between reachable and unreachable is written to the Log with the time. Off by default, saved per engagement (`canary.json`), stops on engagement switch. Tools menu and ⌘K entries.

## 0.25.0
- **Tools › Mail security (SPF, DKIM, DMARC)**: for a domain, MX, SPF (single record, `all` qualifier, DNS-lookup count with include expansion, `ptr`, length), DMARC (policy, pct, sp, rua, alignment), DKIM (about thirty common selectors plus your own, RSA key size from the published key, revoked and testing keys), MTA-STS and TLS-RPT — each line judged pass / info / warn / fail with the reason. Only DNS queries via `dig`. Copy as Markdown; **Create finding** with the issues and records. Tools menu and ⌘K entries.

## 0.24.0
- **Tools tab** with a sidebar for small utilities; first tool: **Version & end-of-life check**. Product search over endoflife.date's ~480 products (names, labels, aliases, multi-word), every release cycle with release / latest / active-support / end-of-life dates and status colour, a verdict for the version you found (current, behind on patches, security fixes only, not maintained, end of life) with the dates, **Create finding** with severity suggested from the verdict, and GitHub release notes rendered as Markdown (repository from endoflife.date's identifiers or typed in; the library's GitHub token is used when present). The product list is cached for a day.
- Targets: **Version** button on a port node sends the product and version from the service line to the check. Tools menu and ⌘K: Version & end-of-life check.

## 0.23.0
- **Plan tab**: the engagement-level test plan, made from a template — built in: External network penetration test, Internal network and Active Directory, Web application, Minimal plan — with phases, items to tick off (status cycle, hints, notes), fill-in fields on the plan (client, reference, tester, dates, scope, rules of engagement, contacts; prefilled from the engagement) and on items (text, multi-line, date, choice, yes/no), progress per phase and overall, Markdown export for the report, duplicate / delete. Plans are saved per engagement (`plans.json`); ⌘K finds plan items.
- **Plan templates**: "Save plan as template" keeps the structure, hints and field definitions of a worked plan (not the answers) as your own template; the Templates editor edits name, summary, fields, phases and items (built-in ones are duplicated first), with JSON export / import to share. Tools menu: New Plan from Template…, Plan Templates…

## 0.22.0
- **Tabs keep their state**: every tab stays mounted and is only hidden, so you come back to the same scroll position, expanded folders, selection and half-typed text.
- **Pause logging** (Log tab): stops recording commands, imports and actions until you resume; a red "Log paused" badge in the top bar resumes on click; pause and resume are logged with the duration.
- **Note → Library**: the books button on a note saves a copy as a Markdown file into the *Personal* collection (or one of your own), so it outlives the engagement.
- **Find in Read mode** (⌘F or the magnifier, notes and library pages): matches highlighted in the rendered page, counter, next / previous, esc to close.
- **What is my IP**: the globe in the top bar fetches your public address on click (api.ipify.org, ifconfig.me or icanhazip.com — only when you click), shows it next to the engagement, copies it from the context menu, offers your local interfaces for $LHOST, and logs a change of address.
- **Chef**: JWT sign (HS256/384/512, none) and verify, PowerShell -EncodedCommand encode/decode, Base58, double URL encoding, JSON string escape/unescape, shell single-quoting; new Units category with data-size and duration conversion.
- Housekeeping: a leftover copy of the first diagram implementation (`Sources/Luik/Diagrams/`) that duplicated the types of the Diagram tab was removed.

## 0.21.0
- New **Diagram** tab for network architecture drawings, per engagement: devices as cards (icon in the kind's colour, name, address) — internet, cloud, attacker, firewall, VPN, router, switch, load balancer, access point, server, web server, database, domain controller, mail server, workstation, laptop, mobile, printer, IoT — links with labels, arrows and dashed/dotted lines, and zones for network segments that carry their nodes when moved. Drag to move (grid snap), drag the dot on a selected node to link, Connect mode, inspector for label/address/notes, right-click menus, undo, zoom and Fit. **From Targets** adds the hosts of the Targets tab with a kind guessed from their open ports; an example network to start from.
- **Export** as PNG (dark or light), SVG, draw.io (.drawio), Mermaid (.mmd) and Luik JSON, or copy the image; **import** draw.io (also compressed pages; containers → zones), Mermaid flowcharts (subgraphs → zones, auto layout) and Luik JSON, from a file or the clipboard. ⌘K finds diagrams by name or by a node's label/address and has "New network diagram". The new tab sits at the end of the tab bar; drag it where you want it.

## 0.20.1
- **Reorder the tabs**: drag a tab in the top bar to a new position (the others slide aside while you drag), or right-click a tab for Move left / Move right / Reset tab order. ⌘1–⌘9, the View menu, ⌘K's "Go to" actions and the shortcuts sheet follow the new order, which is remembered. Reset is also in View › Reset Tab Order and Settings › Appearance.

## 0.20.0
- **Reverse shell generator** (One-liners › Reverse shell, Tools menu, ⌘K): templates come from the Reverse Shell Cheat Sheet in the library (InternalAllTheThings — PayloadsAllTheThings' page now only points there) and from your own one-liners in a "Reverse shells" category; fill in $LHOST/$LPORT (shared with the One-liners tab, antenna button detects the VPN address), choose the shell to spawn (/bin/sh, bash, zsh, …) and an encoding (URL, double URL, base64 pipe, PowerShell -EncodedCommand). Shows the listener to start first (netcat, rlwrap, ncat, socat, pwncat-cs, Metasploit handler), the payload and the TTY upgrade from the same sheet, each with Copy; listener and upgrade paste into the terminal; Copy all steps; **Save as one-liner** stores the three steps with the placeholders. Without the sheet in the library the window explains what to download.

## 0.19.0
- **Multi-step one-liners**: a one-liner can hold several commands that belong together (listener → payload → upgrade), each with an optional label. The editor has Add step and arrows to reorder; the row shows the steps numbered with their own copy / paste buttons and **Copy all** for the sequence; the one-liners panel in Targets shows them the same way. Single-command one-liners are unchanged, and `snippets.json` keeps the old `command` field next to the steps, so older versions still read it. Two defaults became sequences: file transfer over HTTP and over netcat.
- **Reorder one-liners**: drag a row within its category, or right-click › Move up / Move down / Move to top / Move to bottom (and Duplicate); the arrows next to a category heading (and its context menu) move whole categories. The order is saved. The editor also offers the existing categories in a menu.

## 0.18.1
- Markdown tables in Read mode are laid out properly: columns take the width of their content when it fits, otherwise the space is shared in proportion and the text wraps (a horizontal scroll only when the longest words do not fit); header row tinted and bold, zebra rows, column alignment from the delimiter row (`:---:`), `<br>` and `\|` inside cells, inline code and links in cells. Pipe tables are now read by Luik itself before the rest is handed to the system parser, so they render the same everywhere (also inside list items and block quotes); fenced code is left untouched.

## 0.18.0
- **Markdown notes**: notes are rendered Markdown (headings, lists, tables, block quotes, links, inline code) with an Edit / Read switch; in Read mode every code block has a copy button. Rendered with Foundation's own Markdown parser — no third-party code.
- **Library** in the Notes sidebar, shared by all engagements, as plain .md files in `~/Library/Application Support/Luik/Library/`: **Import folder or files…** copies a whole folder of cheat sheets at once (subfolders kept, folder name = collection); documents open in Read mode and can be edited in place; Rescan / Show in Finder for outside edits; filter box over notes and library (titles, then full text); ⌘K searches the library too.
- **Download documentation…** (Notes ⋯ menu, Tools menu, ⌘K): PayloadsAllTheThings and InternalAllTheThings (swisskyrepo) or any GitHub repository of Markdown pages (`owner/name`, optional branch, token for private repositories) are downloaded as an archive, reduced to their Markdown files and shown as a collection with the commit remembered; **Check for updates** / **Update** keep them current; relative links between pages open inside Luik. A knowledge-base record that names a PayloadsAllTheThings page links to it once the documentation is downloaded.
- The GitHub access token is now one keychain item shared by the knowledge-base and library downloads.

## 0.17.0
- **Download a knowledge base** (Knowledge base tab › Download, the empty tab, ⋯ menu, Tools menu, ⌘K): the attack-vectors knowledge base now ships in the repository (`knowledge-base/`, 349 rows, English and Dutch) and is imported with one click. The sheet also takes any link — an .xlsx/.csv/.tsv/.json file on GitHub, GitLab or a web server (GitHub `…/blob/…` links are converted to raw downloads; an optional access token for private repositories is kept in the keychain) — or a `catalog.json` listing a team's own knowledge bases, which can be made the default list in Settings › Tools. The ⋯ menu shows where the imported knowledge base came from; when the catalogue has a newer version, the sheet offers **Update**.
- Create finding from a knowledge-base record: an empty *Evidence* column no longer hides a filled *Test approach* column — the first matching column with a value is used.

## 0.16.1
- **Resize with the mouse**: drag the bottom edge of the panel to change its height (the cursor becomes the up/down arrow and a small grip appears); the new height is stored as the Height setting, so it is kept for the next time. Double-click the edge to return to the default height. The top edge stays put, and the panel cannot be dragged past the Dock or below a fifth of the screen.

## 0.16.0
- **One-liners in Targets**: a one-liner can be tagged with the services and ports it is for (editor › "Show in Targets at": `http, https, 80, 443`, `microsoft-ds, 445`, `host` for every host, `port` for every port). The selected host, port or work-item node shows the matching one-liners in a **One-liners** panel with that node's address and port already filled in — copy, or paste into the terminal (logged). The bundled list is tagged; your own copies of the defaults get the same tags once, and the default web/ssh/ftp commands now use the node's port. **Use … as $RHOST / $RPORT** on the panel makes the node the target for the One-liners tab.
- New placeholders **$RPORT** (field in the One-liners tab; in Targets the node's port) and **$RURL** (`http(s)://host:port` — https for ssl/https services and ports 443/8443, default ports left out, IPv6 bracketed). The export button sets RPORT and RURL in the terminal too; checklist hints understand $RURL as well.

## 0.15.4
- Fix: checklist items with a comma inside parentheses ("Technology fingerprint (headers, whatweb)", "Input testing (injection, XSS, IDOR, upload)", …) were split into several items since 0.15.0. The splitter now respects parentheses, existing checklists are repaired once at launch, and work-item nodes that were created in pieces are glued back together (notes, sub-nodes and status kept).

## 0.15.3
- **Checklists export/import** is now in plain sight: Export (all as JSON, all as Markdown, or only the selected list) and Import… buttons in the editor, plus entries in the Targets ⋯ menu and Settings › Targets. Import understands a full set (asks: merge or replace everything), single checklists (added; same names replaced; "Every system"/"Every port" replace those) and the Markdown export; imported lists get fresh ids.

## 0.15.2
- Build: `build.sh` signs with a local "Luik Local" certificate when one exists (create it once with `scripts/make-signing-identity.sh`), so the Screen Recording permission for evidence screenshots is no longer lost after every rebuild.
- README: screenshots of every tab (docs/screenshots), repository links in lowercase after the rename.
- **Knowledge base template and guide**: the empty Knowledge base tab (and the ? button, ⋯ menu, Help menu and ⌘K) explains which columns Luik recognises and saves an example CSV with those columns and two example rows to start from. A `cvss_vector` column is no longer mistaken for the title.
- **Keyboard shortcuts** sheet (⌘/, ? in the top bar, Help › Keyboard Shortcuts, ⌘K): every shortcut and mouse trick, including your configured hotkey. New Help menu with the template and a link to the repository.

## 0.15.1
- Fix: 0.15.0 did not compile (a property named `set` in the checklist store clashed with Swift's setter keyword).

## 0.15.0
- **Checklist editor** (Targets ⋯ menu › Edit checklists…, Settings › Targets, Tools menu, ⌘K): the work-item nodes are now proper checklists — Every system, Every port (fallback) and one per service — with a name, the service names/port numbers they apply to, an enable switch, drag-to-reorder lists and an optional **hint per item** that becomes the node's starting notes with $RHOST/$RPORT/$LHOST/$LPORT filled in. A tester shows which list a service/port gets; export/import as JSON to share a workflow; "Apply to current targets" adds missing items to existing hosts and ports. Existing customised templates are migrated once.
- **Colour schemes** (Settings › Colours): the Luik default plus ten Sanzo Wada combinations (A Dictionary of Color Combinations, 1933) for panel tint, accent, terminal text, cursor and selection.

## 0.14.2
- Fix: switching to another tab and back wiped the terminal (scrollback gone, prompt redrawn, typed text lost). SwiftUI detached the terminal view and gave it a zero-size frame on the way, which made SwiftTerm reflow the shell to 2×1 cells. The terminal now stays mounted (only hidden) while other tabs are shown, SwiftTerm ignores sizes smaller than a few cells, and the keyboard focus is released when you leave the Terminal tab so keystrokes in Notes never reach the shell.
- Scrollback raised from 500 to 5000 lines per tab.

## 0.14.1
- Fix: typed commands were practically never logged. The old check looked at the pty's ECHO flag, which zsh/bash line editors, ssh and most interactive programs switch off themselves. Luik now reads the command from the screen when you press Enter (the cursor row after the prompt), so commands typed inside ssh sessions, recalled from history or completed with Tab are logged too; passwords never appear on screen and are therefore never recorded, and full-screen programs (alternate buffer) are ignored.

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
