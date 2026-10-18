<p align="center">
  <img src="Resources/AppIcon-preview.png" width="96" alt="Luik">
</p>

# Luik

[![Build](https://github.com/mothproof3512/luik/actions/workflows/build.yml/badge.svg)](https://github.com/mothproof3512/luik/actions/workflows/build.yml)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)
![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange)
[![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)

A Guake-style drop-down app for macOS, built for pentesters: press a hotkey (⌘Esc by default)
and a panel slides down from the top of the screen with nine tabs:

| Tab | What it does |
|---|---|
| **Terminal** | A real terminal (SwiftTerm) with multiple tabs, running your own shell as a login shell |
| **Notes** | Markdown notes per engagement (edit / read, code blocks with a copy button), saved automatically — plus the **Library**: your cheat sheets imported from a folder in one go, and documentation such as PayloadsAllTheThings and InternalAllTheThings downloaded (and updated) from GitHub, all searchable |
| **One-liners** | A list of commands with a **Copy** button; `$RHOST`, `$RPORT`, `$RURL`, `$LHOST` and `$LPORT` are replaced; commands can also be pasted straight into the terminal. Tag a one-liner with service names or ports and it shows up under the matching port in Targets, filled in for that host |
| **Targets** | Import nmap, Nessus, nuclei or masscan output (one host or many IPs at once). One node per system, one node per port, and work-item nodes underneath with status and notes, so you can work systematically; scanner findings become nodes under the port |
| **Findings** | The findings of the engagement with a CVSS 3.1 calculator, affected hosts/services, description/impact/evidence/recommendation/references and status — created by hand, from a target node, from a knowledge-base record or from a Nessus/nuclei import; exported as a Markdown or HTML report |
| **Knowledge base** | Download the attack-vectors knowledge base that comes with Luik (349 rows, English or Dutch) or import your own findings sheet (.xlsx, .csv or .json) — also straight from your own GitHub repository — and search every column instantly: a product name, version string, CVE, CWE or technique; then read the full finding, with links clickable and matches highlighted |
| **Log** | Timestamped activity log: commands pasted from One-liners/Searchsploit, every command you run in Luik's terminal tabs (read from the screen when you press Enter — also inside ssh sessions; passwords never appear on screen, so they are never logged), imports and your own notes — exportable as Markdown for the report |
| **Plan** | The engagement-level test plan from a template (external, internal/AD, web application, minimal, or your own): phases with items to tick off, hints, notes and fill-in fields (client, scope, dates, roles, …), progress per phase, Markdown export for the report — and "Save as template" so a worked plan becomes next time's template |
| **Tools** | A sidebar with everything that is not in the top bar: by default Knowledge base, Searchsploit, Chef and Diagram (move any tab here, or give any tool its own tab) plus the small tools. **Reachability canary**: probe one or two in-scope hosts every N minutes (TCP connect or ping), a badge in the top bar turns red and the Log gets a timestamp the moment one stops answering — off by default, per engagement. **Mail security**: SPF (with the 10-lookup count and include expansion), DMARC policy, DKIM keys (common selectors, key size), MX, MTA-STS and TLS-RPT for a domain, judged and explained, with Create finding. **Version & end-of-life check**: type a product (or press Version on a port node in Targets), see every release cycle with release, support and end-of-life dates from endoflife.date, a verdict for the version you found (current / behind on patches / security-only / end of life) with **Create finding**, and the release notes from GitHub rendered in place |
| **Diagram** | Network architecture drawings per engagement: devices (firewall, router, switch, servers, DC, clients, cloud, …) as cards with icon, name and address, links with labels, arrows and dashed styles, and zones for segments (DMZ, LAN, VLAN). Built by hand, from the hosts in Targets, or imported from draw.io and Mermaid; exported as PNG (dark or light), SVG, draw.io, Mermaid or JSON |
| **Chef** | CyberChef-style data kitchen: build a recipe of operations (Base64/Base32/hex/URL/HTML/Unicode, hashes and HMAC, JWT decode, gzip/zlib, JSON, regex, extractors for IPs/URLs/emails/hashes/CVEs, defang, CIDR, timestamps) and the output updates as you type; a magic detector suggests decodings |
| **Searchsploit** | Exploit-DB search built in: download the official database once, then search it offline like searchsploit, with version-aware matching (`apache 2.4.49` also finds `< 2.4.50` and `2.4.x` entries). Every hit comes with copy-and-paste command lines for the machine where you want the exploit |

Everything is stored locally as JSON in `~/Library/Application Support/Luik/`.

## Screenshots

Each shot uses a different colour scheme (Settings › Colours); the engagement name sits in the
top bar, the tabs are ⌘1 … ⌘9.

<p align="center">
  <img src="docs/screenshots/targets.png" width="100%" alt="Targets: hosts and ports from a scan, checklist nodes with status, and Exploit-DB / knowledge-base suggestions for the selected service">
  <br><sub><b>Targets</b> — hosts and ports from an nmap import, checklist nodes with a status, and the Suggestions panel matching the service version against Exploit-DB and the knowledge base.</sub>
</p>

<table>
  <tr>
    <td width="50%"><img src="docs/screenshots/terminal.png" width="100%" alt="Terminal tab with several shells"><br><sub><b>Terminal</b> — SwiftTerm tabs running your own login shell; saved connections under Connect.</sub></td>
    <td width="50%"><img src="docs/screenshots/one-liners.png" width="100%" alt="One-liners with $RHOST, $LHOST and $LPORT"><br><sub><b>One-liners</b> — commands with Copy / paste-into-terminal buttons; <code>$RHOST</code>, <code>$RPORT</code>, <code>$LHOST</code> and <code>$LPORT</code> filled in from the fields at the top; tagged ones also appear under the matching port in Targets.</sub></td>
  </tr>
  <tr>
    <td><img src="docs/screenshots/findings.png" width="100%" alt="Findings tab with a finding created from a target node"><br><sub><b>Findings</b> — severity, status, CVSS 3.1 calculator, affected hosts/services and the report sections; this one was created from a Targets node.</sub></td>
    <td><img src="docs/screenshots/knowledge-base.png" width="100%" alt="Knowledge base with scope, severity and phase filters"><br><sub><b>Knowledge base</b> — your own findings sheet, searchable across every column, with scope / severity / kill-chain-phase filters, Add to target and Create finding.</sub></td>
  </tr>
  <tr>
    <td><img src="docs/screenshots/searchsploit.png" width="100%" alt="Searchsploit tab with copy-and-paste command lines"><br><sub><b>Searchsploit</b> — Exploit-DB offline, with ready-made command lines per hit.</sub></td>
    <td><img src="docs/screenshots/chef.png" width="100%" alt="Chef tab identifying an Atlassian PBKDF2 hash"><br><sub><b>Chef</b> — recipes of operations; here <i>Identify hash</i> recognising an Atlassian <code>{PKCS5S2}</code> hash and suggesting the hashcat / john command.</sub></td>
  </tr>
  <tr>
    <td><img src="docs/screenshots/notes.png" width="100%" alt="Notes tab"><br><sub><b>Notes</b> — Markdown notes per engagement, saved automatically, with the library of cheat sheets and downloaded documentation in the sidebar.</sub></td>
    <td></td>
  </tr>
</table>

## Installing

### Option 1: build it yourself (recommended)

Requires macOS 14 (Sonoma) or newer and Xcode **or** just the Command Line Tools
(`xcode-select --install`). No other dependencies: SwiftTerm is bundled as source in
`Vendor/`, so the build needs no network access.

```bash
git clone https://github.com/mothproof3512/luik.git
cd Luik
./build.sh --install     # builds build/Luik.app, copies it to /Applications and launches it
```

Build only: `./build.sh` (result in `build/Luik.app`). Launch without installing: `./build.sh --run`.
If you have Xcode, you can also open `Package.swift` in Xcode and build/debug from there.
A locally built app launches without fuss: it is ad-hoc signed and not quarantined.

### Option 2: ready-made download

For every `v*` tag, GitHub Actions builds a `Luik.app.zip` and attaches it to the
[releases](https://github.com/mothproof3512/luik/releases). That app is not notarized (that
requires a paid Apple Developer account), so Gatekeeper blocks it after download. Fix: unzip,
drag `Luik.app` to `/Applications` and remove the quarantine flag once:

```bash
xattr -dr com.apple.quarantine /Applications/Luik.app
```

(Or: System Settings › Privacy & Security › "Open Anyway" after the first attempt.)

Luik has no Dock icon; you find it as a ⌄ icon in the menu bar (show/hide, settings, quit).

## Usage

- **Hotkey**: **⌘ Esc** by default. To change it: gear icon top right › General › click the hotkey
  field › press the key or combination you want (e.g. F12 like Guake, ⌃`, ⌥Space, ⌘⇧T).
  A bare Esc cancels recording, ⌫ clears the hotkey. The list icon next to the field offers a
  few common choices. Letters and digits only work together with ⌃, ⌥ or ⌘, otherwise you could
  never type that key again. If macOS cannot register the combination (because another app
  already owns it), you see that right under the field. If you pick a function key: on a MacBook
  keyboard that is `fn`+F-key, unless "Use F1, F2, etc. keys as standard function keys" is
  enabled (System Settings › Keyboard).
- The panel appears on the screen the mouse is on, 55% high and full width by default. Drag the
  bottom edge to change the height (a grip appears when the mouse is over it; the new height is
  kept as the Height setting), double-click the edge to go back to the default; width and height
  are also sliders in Settings › Appearance.
- **Transparency**: Settings › Appearance › *Background opacity* applies to the whole panel
  (every tab). *Blur* blurs what is behind it (macOS HUD style); turn blur off for full
  transparency like Guake. *Extra terminal opacity* adds a dark layer under the terminal text only.
- **Corners and animation**: Settings › Appearance › *Corner radius* (0 = square) and *Round the
  top corners too*; *Animation* sets how fast the panel slides down (all the way left = instant,
  no animation).
- Every tab stays exactly as you left it when you switch away and back: scroll position, expanded
  folders, selection, half-typed text.
- The **globe** in the top bar asks a lookup service for your public (exit) IP when you click it —
  never automatically — and shows it next to the engagement; right-click to copy it or to put one
  of your local interfaces (VPN first) into `$LHOST`. A change of public IP is written to the Log.
- **Tabs and Tools**: the top bar holds the tabs you use all day (Terminal, Notes, One-liners,
  Targets, Findings, Plan, Log, Tools); the **Tools** tab has a sidebar with the rest — Knowledge
  base, Searchsploit, Chef, Diagram, Version check, Mail security, Canary. Drag tabs to reorder
  them; right-click a tab › *Move into Tools* parks it in the sidebar, right-click a tool › *Give
  it a tab* brings it to the top bar; *Reset tabs and tools* (also View menu and Settings ›
  Appearance) restores the default. ⌘1–⌘9, the View menu and ⌘K "Go to" follow your layout.
- By default the panel hides as soon as another app gets focus (can be turned off in settings).
  When hiding, the app you were using before gets focus back.

### Keyboard shortcuts inside the panel

The full list, including mouse tricks and your own hotkey, is one keystroke away in the app:
**⌘/** (or the ? button in the top bar, Help › Keyboard Shortcuts, or ⌘K → "Keyboard shortcuts").

| Keys | Action |
|---|---|
| ⌘1 … ⌘9 | The tabs in the order of the top bar (default: Terminal / Notes / One-liners / Targets / Findings / Knowledge base / Searchsploit / Chef / Log) |
| ⌘T, ⌘W | New / close terminal tab |
| ⌘⇧] , ⌘⇧[ | Next / previous terminal tab |
| ⌘C / ⌘V | Copy / paste (also in the terminal) |
| ⌘K | Search everything |
| ⌘N | New finding |
| ⌘⇧E | Capture evidence screenshot (⌘⌥⇧E keeps Luik visible) |
| ⌘F / ⌘G / ⌘⇧G | Find in the terminal scrollback (and in text fields) |
| ⌘, | Settings |
| ⌘Q | Quit Luik |

### Notes and the library

- Notes are **Markdown**. The control at the top right switches between **Edit** (plain text,
  monospaced) and **Read** (rendered: headings, lists, tables, quotes, links, and code blocks with
  a **copy** button). The choice is remembered. Each engagement has its own notes. In Read mode
  **⌘F** (or the magnifier) opens a find bar: matches are highlighted in the page, with next /
  previous and a counter — also for long library pages.
- The **books** button on a note saves a copy into the library (collection *Personal*, or one of
  your own), so what you learned during an engagement stays available in the next one. The note
  itself stays with the engagement.
- The **Library** in the sidebar is shared by all engagements and lives as plain `.md` files in
  `~/Library/Application Support/Luik/Library/<collection>/`:
  - **⋯ › Import folder or files…** copies a folder of cheat sheets in one go (subfolders kept; the
    folder name becomes the collection) or loose `.md` files (into "Cheatsheets"). Edit them in Luik
    (saved back to the file) or in any editor — **Rescan** picks up outside changes; **Show in
    Finder** opens the folder.
  - **⋯ › Download documentation…** fetches **PayloadsAllTheThings** and **InternalAllTheThings**
    (swisskyrepo, MIT) or any GitHub repository of Markdown pages you add (`owner/name`, optional
    branch; a token for private repositories, kept in the keychain). Luik downloads the repository
    archive, keeps the Markdown files and remembers the commit; **Check for updates** compares with
    GitHub and **Update** replaces the copy. Links between pages open inside Luik.
  - The filter box searches notes and the whole library (titles first, then full text); ⌘K finds
    library pages too, and a knowledge-base record that names a PayloadsAllTheThings page gets an
    **Open in the library** link once that documentation is downloaded.

### Diagram

- **New diagram** (or *Start from the example*, or *From Targets*). Click the canvas where the next
  device should go, then use **Add** (all kinds, grouped) or the quick icons (firewall, router,
  switch, server, workstation). Drag nodes around — they snap to the grid.
- **Linking**: select a node and drag the dot on its right onto another node, or switch on
  **Connect** and click two nodes. Select a link to give it a label (`443/tcp`, `IPsec`, `VLAN 20`),
  a dashed or dotted line, or an arrow (direction of traffic or trust).
- **Zones** are network segments drawn behind the nodes: drag to move them (the nodes inside move
  along), drag the corner to resize, pick a colour, name them `DMZ — 172.16.10.0/24`.
- **From Targets** adds a node for every host in the Targets tab that is not in the drawing yet,
  with a kind guessed from its open ports (88 + 389 → domain controller, 1433/3306/5432 → database,
  80/443 → web server, …) and the open ports in its notes.
- Right-click for more (change kind, link from here, duplicate, link style, send a zone to the back);
  ⌫ deletes, esc stops connecting, **Undo** reverts the last change, zoom and **Fit** at the top.
- **Export**: PNG (dark like the panel, or light for reports), SVG, draw.io (`.drawio`, opens in
  diagrams.net / draw.io desktop / Confluence), Mermaid (`.mmd`, for Markdown wikis, GitLab and
  GitHub) and Luik JSON; **Copy image** puts a PNG on the clipboard.
  **Import**: draw.io files (uncompressed and compressed pages; containers become zones), Mermaid
  flowcharts (`graph LR`/`TD`, subgraphs become zones, shapes and labels pick the kind, a second line
  with an IP becomes the address; laid out automatically) and Luik JSON — also straight from the
  clipboard. Each engagement keeps its own diagrams in `diagrams.json`.

### One-liners

- Fill in **$RHOST** (the target), **$RPORT**, **$LHOST** (your own address — the antenna button
  detects it, preferring VPN tunnels such as utun/tun) and **$LPORT**; they are replaced in commands
  when copying or pasting. **$RURL** becomes `http(s)://$RHOST:$RPORT` (https for ssl/https services
  and ports 443/8443, default ports left out). **export** runs `export RHOST=… RPORT=… RURL=…
  LHOST=… LPORT=…` in the active terminal tab so the variables work there too. The older forms
  `<ip>`, `<target>` and `$TARGET` still work.
- **Copy** puts the command on the clipboard; the terminal icon pastes it into the active terminal
  tab (without Enter, so you can still edit it).
- **Steps**: a one-liner can be several commands that belong together — a listener on your
  machine, the payload on the target, the upgrade afterwards. Add steps in the editor (each with an
  optional label such as "On the target"), reorder them with the arrows; the row shows them
  numbered with their own copy / paste buttons and **Copy all** for the whole sequence, also at the
  matching port in Targets.
- **Order**: drag a row to move it within its category (or right-click › Move up / down / to top /
  to bottom); the arrows next to a category heading move whole categories. The order is kept.
- **Reverse shell** (button in the toolbar, Tools menu, ⌘K): a generator that reads the templates
  from the *Reverse Shell Cheat Sheet* in your library — download **InternalAllTheThings** (where
  the sheet lives now; PayloadsAllTheThings only points to it) — plus your own one-liners in a
  category named *Reverse shells*. Pick a template (Bash, Python, PHP, PowerShell, …), fill in
  `$LHOST`/`$LPORT` (shared with the One-liners tab), choose the shell to spawn and an encoding
  (URL, double URL, base64 pipe, PowerShell `-EncodedCommand`); the sheet shows the listener to
  start first (netcat, rlwrap, ncat, socat, pwncat-cs, Metasploit handler), the payload and the TTY
  upgrade from the same cheat sheet, each with Copy (the listener and the upgrade also paste into
  the terminal). **Save as one-liner** keeps the three steps with the placeholders, so they follow
  `$LHOST`/`$LPORT` later. Nothing is bundled: the templates update with the documentation.
- **Show in Targets at** (in the editor): service names and/or port numbers (`http, https, 80, 443`,
  `microsoft-ds, 445`), `host` for every host or `port` for every port. Tagged one-liners appear in
  the **One-liners** panel of the matching host/port in Targets (see below) with the host and port of
  that node filled in. The bundled list is tagged already; the capsule next to the title shows the tags.
- Edit, delete and add in the app; the list lives in `snippets.json`. The bundled list contains
  recon and enumeration commands as a starting point — change it as you like.

### Targets (nmap, Nessus, nuclei, masscan)

1. Click **Import scan** and paste the output, or choose one or more files; the format is detected.
   Supported: nmap normal screen output (`nmap ...` / `-oN`), grepable (`-oG`) and XML (`-oX`);
   Nessus exports (`.nessus`); nuclei JSON (`-json`, `-jsonl`, `-je`); masscan (`-oL`, `-oJ`, `-oG`).
   Tip: scan with `-oA scans/name` and you have all three nmap formats. Large files (Nessus exports)
   are imported straight away instead of being loaded into the text box.
   For Nessus and nuclei you choose from which severity a **node per scanner finding** is added under
   the port (plugin name, severity, synopsis/description/solution/output in the notes) and from which
   severity an entry in the **Findings** tab is created — one per plugin/template with every affected
   host:port, merged into the existing entry when you import again.
2. Every host gets a node (IP + hostname), with underneath:
   - a node per open port (service/version as subtitle, NSE script output in the notes),
   - under every port the **work-item nodes** from the checklist for that service — SMB, HTTP,
     SSH, LDAP, Kerberos, MSSQL, SNMP, RDP and about twenty more have their own; ports with no
     match get the generic list (Enumeration, Versions & CVEs, Misconfigurations, Credentials,
     Exploitation, Notes),
   - under the host itself the system checklist (Recon & enumeration, Vulnerabilities, Initial
     access, Privilege escalation, Post-exploitation & loot).
3. Importing the same host(s) again only adds new ports/information; nothing is duplicated.
4. Every node has a status (click the circle: to do → in progress → done → N/A) and a notes field.
   Hosts and ports show their progress (handled/total). Right-click for sub-nodes, status or delete.
5. The checklists are yours to change (see below). The ⋯ menu exports everything as Markdown.
6. Select a port node and the **Suggestions** panel shows matching Exploit-DB entries (product and
   version taken from the nmap service description, version-aware) and knowledge-base findings;
   one click opens the hit in its own tab.
7. The **One-liners** panel on a host, port or work-item node lists the one-liners tagged for that
   host or service (`http` on 10.10.10.5:8080 → `whatweb -a 3 http://10.10.10.5:8080`, …) — copy, or
   paste into the terminal; **Use … as $RHOST / $RPORT** makes the node the target for the One-liners
   tab, the export button and the saved connections.

### Checklists — your own workflow

**Edit checklists…** (Targets ⋯ menu, Settings › Targets, Tools menu or ⌘K) opens the editor:
on the left **Every system**, **Every port** (the fallback) and one checklist per service; on the
right the list's name, the keys it applies to and its items. Keys are service names as nmap and
Nessus report them (`http`, `ssl/http`, `microsoft-ds`, `ms-sql-s`, …) and/or port numbers; the
first matching list wins, so order matters (drag or use the arrows). Every item becomes a work-item
node with a status; an optional **hint** on an item is written into the node's notes when the node is
created, with `$RHOST`, `$RPORT`, `$RURL` (and `$LHOST`/`$LPORT` from One-liners) filled in — the place for
the commands you always run and the things you always check for that service. A tester at the
bottom shows which list a given service/port would get. Checklists live in `checklists.json` in the
data folder, shared by all engagements. **Export** writes all of them as JSON (for Luik) or Markdown
(for a wiki or repository — importable too), or just the selected list; **Import** reads such a
file and asks whether to merge (same-named lists replaced, others kept) or replace everything, while
a file with single checklists is simply added. Both are also in the Targets ⋯ menu and Settings ›
Targets. **Apply to current targets** adds missing items to the hosts and ports you already have.

### Colour schemes

Settings › Colours offers the Luik default plus ten combinations from Sanzo Wada's *A Dictionary
of Color Combinations* (1933): from each combination the darkest colour becomes the panel tint, the
lightest the terminal text and the most saturated one the accent — buttons, selected tab, cursor
and selection. Opacity and blur from the Appearance tab still apply on top. The colour values come
from Matt DesLauriers' [dictionary-of-colour-combinations](https://github.com/mattdesl/dictionary-of-colour-combinations) dataset (MIT).

### Findings and the report

Every finding has a title, severity, an optional CVSS 3.1 vector (the calculator shows the eight
base metrics as pickers plus temporal metrics; paste a vector from an advisory and press Apply; the
severity follows the score), the affected hosts/services (one per line; **Add** inserts the selected
Targets node), description, impact, evidence (the camera button links a screenshot here),
recommendation, references, a status (open → confirmed → reported → resolved / false positive) and a
source. Findings come from four places: the **+** button, the **Finding** button on a Targets node
(its notes become the evidence, host:port the affected service), **Create finding** on a knowledge-base
record (description/impact/recommendation/references are mapped by column name) and Nessus/nuclei
imports. The ⋯ menu exports the whole set as a **Markdown** or **HTML report** (summary table, then
one section per finding, most severe first); Word opens the HTML directly (File › Open) and
`pandoc findings.html -o findings.docx` makes a .docx.

**Keep what you learned.** The books button on a finding saves it as a record of your own in the
Knowledge base (table *My findings*, file `my-knowledge.json`, outside any engagement and
untouched by re-importing or removing the downloaded knowledge base): title, severity, CVSS
vector, description, impact, recommendation and references — not the evidence or the affected
hosts. The finding's source becomes `KB MY-001`, so pressing the button again updates that record
instead of adding another. Own records are searched together with the imported sheet, show up in
the port-node suggestions and ⌘K, can be edited and deleted in the Knowledge base tab (Edit /
trash on the record; ⋯ › *Show only my records*), and **Create finding** on one brings it back
into the next engagement.

**Screenshots under Evidence.** Every image linked in the evidence text (the camera button's
`![evidence](path)` links, **Add image…**, or a pasted path) shows as a thumbnail below the field.
Click one to open the annotator: arrow, box, circle, text label, highlight, **blur** (pixelated) and
**redact** (solid black) for passwords, hashes, names and anything else that must not reach the
report; colours and line widths, drag to move a mark, ⌘Z / ⌘⇧Z, ⌘⌫ removes the selected mark. The
marks are burnt into the pixels at the original resolution, so a blurred or redacted area cannot be
recovered from the saved file. **Save** writes `<name>-annotated.png` next to the original and points
the evidence link at it; tick **Replace original** to overwrite the file instead. Right-click a
thumbnail for Show in Finder, Copy path or removing the link.

### Images in the library

Pictures belong next to the cheat sheets: an HLD from the client, a network drawing, an
architecture screenshot. Library ⋯ › **Import images…** (or *Import folder or files…* with images
among the files; a folder import keeps the images that sit next to its Markdown) puts them into the
*Images* collection; they show with a photo icon in the outline and open in a viewer with Fit /
50 / 100 / 200 %, copy, open in Preview and show in Finder. A Markdown page whose line is only an
image (`![HLD](images/hld.png)`, relative to the page, or an absolute path) now renders that
image inline — in notes as well — with double-click to open it. Diagram › Export › **Save to
Library** stores a light PNG of the drawing there, and the evidence thumbnails in Findings offer
*Save a copy to the Library*.

### Web application and identity elements in diagrams

Besides the network devices, the Add menu has a **Web application** group (user / browser, CDN,
WAF, reverse proxy / API gateway, web application, API, service, message queue, cache, object
storage, container / cluster, serverless function, third-party API) and an **Identity & auth**
group (identity provider / SSO, authorization server (OAuth 2.0 / OIDC), MFA, directory (LDAP),
session / token store, secrets vault, certificate authority). *New from example: web application*
gives a starting point — user → CDN/WAF → gateway → app/API → data, with the identity side as its
own zone and the login redirect, code → token and JWKS/introspection flows drawn as directed
links. draw.io and Mermaid imports recognise the usual names (Okta, Keycloak, Entra, Kong, Redis,
Kafka, S3, Lambda, …).

Cards grow with their label so the full name is always readable; the status bar's **Show** picker
puts the address, the first line of the notes or the kind on the second line of every card.
Right-click a node, link, zone or the empty canvas for the context menu (kind, link from here,
duplicate, style, arrow, send to back, add node / zone here, delete).

Nodes that exist in Targets carry badges (ports, findings — red when high or critical) and a green
ring when they are the current target; right-click gives *Open in Targets*, *Use as $RHOST*,
*Open a terminal for …* or *Add to Targets*. From Targets, right-click a host › *Show in diagram*.

Add › **Groups** places a ready-made set in one go (Active Directory, web application, identity,
cloud landing zone, DMZ); PNG exports carry a title block and legend unless switched off in the
Export menu.

### Diagram templates

**New from template** (diagram menu, or *Start from a template* on an empty tab) offers fifteen
starting points, five per group: *Web application set-ups* (classic three-tier, SPA + REST API,
microservices on Kubernetes, serverless, monolith with CMS / webshop), *Authentication flows*
(OAuth 2.0 authorization code + PKCE, enterprise SSO with SAML / OIDC, session-based login,
machine-to-machine with client credentials / API keys, Active Directory Kerberos / NTLM) and
*Network layouts* (small office, DMZ with two firewalls, segmented enterprise with VLANs, hybrid
cloud hub-and-spoke, remote access with VPN and jump host). Each comes with zones, labelled links
and example addresses to overwrite with the client's.

### Network map from Targets

Diagram › **From Targets › Build a network map** makes a new diagram from everything in Targets:
one zone per /24 (hostnames and IPv6 in *Other hosts*), a gateway per segment (the `.1` host
when it is in Targets, else a router placeholder), your attacker node (`$LHOST`) linked to every
gateway, and the hosts in a grid inside their zone — kind guessed from the open ports, open ports
in the notes. *Add missing hosts to this diagram* keeps the old behaviour of adding nodes to the
current drawing. Rearrange, rename zones, export.

### Retest

For a retest, Findings › ⋯ › *Import findings for retest…* brings in the findings of an earlier
engagement on this Mac or a `findings.json` from a close-out export: status Open, outcome "not
retested", the original engagement and title as reference, the original evidence kept as a note.
Each finding then has a Retest section — outcome (fixed, partially fixed, still open; fixed also
resolves it), date, notes — and *Copy retest table as Markdown* produces the comparison with
counts per outcome. The Retest plan template walks the engagement.

### Close-out

When the engagement ends, *Close-out export…* (engagement menu, Tools menu, ⌘K) writes
everything into one folder and a zip: a README with scope and counts, `findings.md` /
`findings.html`, `targets.md`, `hosts/` with a dossier per host, `plans/`, `activity-log.md`
with the captured outputs, `notes/`, `diagrams/` (PNG + JSON), `evidence/` and `data/` with the
raw JSON. Tick what goes in; nothing is removed from Luik.

### First start and updates

The first start shows a welcome sheet with the four steps that make Luik useful on a new Mac
(knowledge base, documentation, shell integration, engagement), each one button, plus a fictional
**demo engagement** to look at; it stays reachable under Help › *Welcome to Luik…*. Once a day after launch Luik can compare what you
downloaded (library sources, knowledge base) and Luik itself with GitHub and show a green
*Updates (n)* badge — nothing is downloaded by itself, and both checks can be switched off in
Settings › General, after which Luik makes no network requests on its own.

### Commands, checklists and pages are one thing

A one-liner and a checklist item can carry a *Read more* link: a library page (picked with the
book button in the editor, or a topic such as "SMB"), or a URL. Without one, Luik finds the page
named after the service (microsoft-ds → SMB, ms-wbt-server → RDP, …). Book icons on one-liner rows
and a *Read more* line on port and work-item nodes open the page in the Notes tab; a library page
in turn shows the one-liners that point at it (copy / paste) and the checklist items that link
to it.

### Luik learns, and playbooks travel

Every copy or paste of a one-liner is counted per service (`usage.json`, global). At a port node
the one-liners you used at that service before come first, marked "· 3×"; the One-liners tab
opens with a *Most used* section. Checklist items marked done or n/a on a port are counted as
well, and the checklist editor shows the totals — an item that is mostly n/a probably does not
belong in the template. Tools › **Export Playbook…** packs one-liners, checklists, your own plan
templates and your knowledge records into one `.luikplaybook.json` for another Mac, a colleague
or a team repository; **Import Playbook…** merges one. Engagement data, usage counts and
credentials never leave with it.

### The current target

The top bar shows the host you are working on — `$RHOST[:$RPORT]` from the One-liners variables —
red when it lies outside the engagement's scope. Selecting a host or port in Targets sets it
(Settings › Logging switches that off); the chip's menu switches host or port, shows it in
Targets, opens a terminal for it or clears it. *Open a terminal here* (right-click a host or
port) starts a tab named after the host with `RHOST`, `RPORT`, `LHOST` and `LPORT` in its shell
environment, so `nmap $RHOST` works without the One-liners tab; every command in that tab is
tagged with the host in the Log. A host node shows *Activity for this host* (its commands and
events, with a pin button for outputs), and *Copy host dossier as Markdown* writes one page with
ports, notes, checklist state, findings, commands and evidence files. A command that names a host
outside the scope is not blocked, but gets a red note, a beep and a ⚠️ line in the Log.

### Command output, evidence and automatic imports

Luik already reads the command you run from the screen when you press Enter; since 0.33 it also
keeps **what the command printed** (until the next prompt) next to that Log entry — per
engagement, in `outputs/`, the last 1500 commands, 1 MB each. What never reaches the screen
(passwords) or lives in the alternate screen (vim, less, htop) is never captured. In the Log,
*Output · n lines* folds the text open; the pin button (or **⌘⇧P** in the terminal for the last
command) puts command + output + time as a Markdown block into the selected finding's Evidence,
the selected target's notes or a new note. A finding thus carries the exact command, its output
and the moment — reproducible without copy-and-paste.

**Shell integration.** Settings › Logging › *Install for zsh* (or bash) adds one `source` line
to your rc file; the script only runs inside Luik's tabs and prints OSC 133 prompt markers (as
iTerm2 and VS Code use). Luik then takes the output boundaries from the shell — exact with
two-line prompts and when you type ahead — and records each command's exit status (`exit n`
badge in the Log). Without it the Enter-key heuristic is used.

When the output looks like a scan — nmap (normal, -oG, -oX), nuclei (console lines or JSON),
masscan — its hosts, ports and findings go into Targets automatically when the prompt returns,
through the same merge as a manual import (Settings › Logging switches it off; the Log then shows
an Import button and a badge with the format).

### Log → one-liner

A command in the Log (pasted by Luik or typed in a Luik terminal) that turned out to be worth
keeping: the bookmark button (or right-click › *Save as one-liner…*) opens the One-liners editor
with the command, the current `$RHOST`, `$RPORT`, `$LHOST` and `$LPORT` values put back as
placeholders and the category *From log* — adjust the title and services, save, and it is there
for the next engagement.

### Plan — the test plan of the engagement

1. **+** (or Tools › New Plan from Template…, ⌘K) and choose a template: *External network
   penetration test*, *Internal network and Active Directory*, *Web application*, *API
   assessment*, *Cloud configuration review*, *Wireless assessment*, *Mobile application
   assessment*, *Phishing and awareness campaign*, *Retest*, *Minimal plan*, or one of your own. Client, reference and scope are prefilled from the engagement.
2. The sidebar lists the plan's phases with their progress; the right side shows the engagement
   details (fill-in fields: text, multi-line, date with a Today button, choice, yes/no) and the
   selected phase with its items. Click the circle to cycle an item's status (to do → in progress →
   done → N/A), expand an item for its hint, item fields and notes; right-click to move or delete;
   **Add item** / phase menu › Mark all done. Everything is saved as you type, per engagement.
3. **Copy / Export as Markdown** (⋯ menu or right-click the plan) writes the fields and every phase
   as a table of status, item and notes — the "performed work" chapter of the report.
4. **Save plan as template…** turns the worked plan into your own template: structure, hints and
   field definitions are kept, statuses and answers dropped. That is how the plan improves with
   every engagement. **Templates…** opens the editor: name, summary, engagement fields, phases and
   items with hints and item fields (e.g. a Result choice); built-in templates are duplicated to
   edit; export / import as JSON to share them with a team. Templates live in
   `plan-templates.json` in the data folder, plans in `plans.json` of the engagement.

### Tools › Version & end-of-life check

Type a product name — endoflife.date tracks about 480 (web servers, languages, databases, operating
systems, appliances, frameworks); aliases and multi-word names like "apache httpd" work — and pick
it from the list; add the version you found. Luik shows every release cycle with release date,
latest patch, active-support and end-of-life dates and a status colour, and a verdict for your
version: current, behind on patches, security fixes only, not maintained, or end of life, with the
dates to quote. **Create finding** writes an "Outdated …" finding with those facts (severity
suggested from the verdict; adjust it). The release notes come from GitHub when endoflife.date
knows the repository (or enter `owner/name`), rendered as Markdown. On a **port node in Targets**
the **Version** button sends the product and version from the nmap service line straight here. The
product list is cached for a day; only the product you pick is fetched.

### Tools › Mail security (SPF, DKIM, DMARC)

Enter a domain and press **Check**: Luik queries DNS through `dig` (your normal resolver, nothing
else) for MX, SPF, DMARC, DKIM, MTA-STS and TLS-RPT and judges what it finds — no SPF or more than
one record, `+all` / `?all` / `~all`, the DNS-lookup budget (includes are expanded and counted, over
10 is a permerror), `ptr`; DMARC missing, `p=none`, `pct` below 100, `sp=none`, no `rua=`; DKIM keys
for about thirty common selectors (add your own from a mail's `DKIM-Signature: s=…`) with the RSA
key size from the published key, revoked and testing-mode keys. Every line says why it matters.
**Copy as Markdown** for the report; **Create finding** writes "Weak email authentication for
<domain>" with the issues and records (severity from the worst issue).

### Tools › Reachability canary ("am I blocked?")

Pick one or two hosts that are in scope and expected to answer — from Targets (host:port with an
open port, or ping) or by hand — choose the interval (1 min to 1 hour) and enable it for the
engagement. Luik then does a TCP connect (or one ICMP echo via `ping`) per target on that interval
and shows a badge in the top bar: green while everything answers, red with the count when something
does not; the moment a target changes from reachable to unreachable (and back) is written to the
Log, which is the timestamp to quote when a block is discussed with the client. Each target shows
latency, last check, last change and a strip of recent results. Every probe is traffic to the
client's systems, so it is off by default, per engagement, and stops when you switch engagement.

### Engagements and scope

The briefcase menu in the top bar switches between engagements. Targets, notes, findings, the log and
the evidence screenshots (a subfolder per engagement) are kept apart; one-liners, the knowledge base,
Exploit-DB, Chef recipes and connections are shared. **Manage engagements…** holds client, reference,
period, notes and the **scope**: one entry per line as CIDR (`10.0.0.0/24`), address, range
(`10.0.0.10-10.0.0.20` or `10.0.0.10-20`), hostname (`example.com` covers its subdomains, `*.example.com`
too) or IPv6 prefix, plus exclusions that win over the scope. A **Check** field tells you whether an
address is in scope; hosts outside the scope get an orange shield in Targets and are listed in the
import summary. Existing data from before 0.14 lands in the "Default engagement" automatically.

### Knowledge base

0. **Download** (Knowledge base tab, Tools menu or ⌘K) fetches a ready-made knowledge base from
   this repository: the [attack-vectors knowledge base](knowledge-base/README.md) — 349 attack
   vectors and CVEs across web, API, network, Active Directory, cloud, mobile, wireless, social
   engineering, physical, endpoint and AI/LLM, with default severity, description, impact, test
   approach, remediation and detection note, mapped to OWASP Top 10 2025, WSTG, ASVS 5.0, MITRE
   ATT&CK, CWE, CISA KEV and more — in **English** or **Dutch**. The same sheet takes a link to
   your own file (GitHub, GitLab, a web server; GitHub `…/blob/…` links are converted, an access
   token covers private repositories and is kept in your keychain) or to a *catalogue* of your
   team's knowledge bases; **Settings › Tools › Knowledge base catalogue** makes such a catalogue
   the default list. When the catalogue has a newer version of what you imported, the sheet shows
   **Update**. The format is described in [knowledge-base/README.md](knowledge-base/README.md).
   Prefer your own sheet? The empty tab explains which columns Luik recognises, and **Save example
   template…** (also in the ⋯ menu, the ? button, Help menu and ⌘K) writes a CSV with those columns
   (`id, title, scope, severity, cvss_vector, kill_chain_phase, description, impact, recommendation,
   references, how_to_test, tags`) and two example rows: open it in Excel or Numbers, replace the
   examples, save as .xlsx or .csv and import it.
1. Click **Import** and choose your findings sheet: an Excel file (`.xlsx`), CSV/TSV or JSON. Every
   sheet in the workbook becomes a searchable table; the header is the first row with at least two
   filled cells, so a title row above the real header is fine. No third-party code is involved: the
   .xlsx is unpacked with the system's `unzip` and read with Foundation's XML parser.
2. Type in the search field: every term must occur somewhere in the row (any column); use
   `"quotes"` for a phrase. Hits in the ID or title column rank first. Columns named like
   *Scope*/*Category*, *Severity*/*CVSS* and *Kill chain phase*/*Tactic* become filter menus
   automatically (phases are listed in attack order).
3. Select a hit to read the whole finding: every non-empty column, search terms highlighted, URLs
   clickable. **Copy as Markdown** puts it on the clipboard; **Add to target** appends it to the
   notes of the node currently selected in the Targets tab.
4. A re-import replaces the previous copy; **Remove knowledge base** (⋯ menu) deletes Luik's copy.
   The imported data lives only in `~/Library/Application Support/Luik/knowledgebase.json` — the
   app itself contains no knowledge base, and nothing but the download request leaves the Mac.

### Searchsploit

1. Click **Download** once: Luik fetches Exploit-DB's own `files_exploits.csv` (about 10 MB, the
   file searchsploit searches) from the official GitLab repository and keeps it in its data folder.
   No network is needed afterwards; click **Update** whenever you want the latest entries. Without
   internet access, import the file from a local searchsploit installation instead (⋯ menu; a
   Homebrew/Kali copy is detected automatically).
2. Search like you would with searchsploit: all terms must match (title, platform, type, CVE codes,
   tags, path), `"quotes"` keep a phrase together, `CVE-…` works too. Version-like terms are matched
   smartly: `apache 2.4.49` finds exact mentions first, then ranges such as `< 2.4.50`,
   `2.4.0 - 2.4.49` or `2.4.49 and prior`, then families such as `2.4.x` or `2.4`.
3. Filter on platform and type, show verified entries only, hide DoS entries, and sort by relevance
   or date.
4. Select a hit for the command lines, each with a Copy button (or **Copy all commands**):
   `searchsploit -m/-x/-p <id>`, the Kali path, `wget`/`curl` downloads of the exact file from
   GitLab or exploit-db.com, a run/compile hint based on the file type, and a one-liner to serve the
   file to another machine. The terminal icon pastes a command into Luik's own terminal.

### Search everything (⌘K)

One box over notes, one-liners, targets (hosts, ports, work items), findings, knowledge-base records,
Exploit-DB, Chef operations, the log, engagements ("Switch to …") and actions such as "Go to Targets",
"New finding" or "New terminal tab".
↑↓ to choose, ↩ to open the hit in its own tab, esc to close.

### Evidence screenshots (⌘⇧E)

Runs macOS's own `screencapture -i`: drag an area, or press space and click a window. The PNG is
saved with a timestamp in `~/Documents/Luik Evidence` (Settings › Tools), a Markdown image link is
appended to the notes of the selected target node, and the capture is written to the Log. By default
Luik hides itself first so you can capture what is behind it; ⌘⌥⇧E keeps it visible. macOS asks once
for Screen Recording permission.

### Terminal connections

The **Connect** menu in the terminal tab bar holds saved connections (ssh with a jump host, a
Kali box, …): each is a command that opens in a new tab, with `$RHOST`/`$LHOST`/`$LPORT` filled in.
⌘F opens SwiftTerm's find bar to search the scrollback.

### Log

Everything that happens during an engagement, with a timestamp: commands pasted into the terminal
from One-liners or Searchsploit, every command you run in Luik's terminal tabs, scanner and
knowledge-base imports, findings added to targets, evidence screenshots and notes you add yourself.
Filter by kind, search, copy or export as Markdown grouped per day. **Pause logging** stops all
recording for a while (client data, secrets); a red "Log paused" badge in the top bar shows it and
resumes on click; the pause and the resume are themselves logged, with the duration.

Typed commands are taken from the screen at the moment you press Enter: the text on the cursor row
after the prompt. That makes it work in every shell and interactive program (zsh/bash line editors,
ssh sessions on other machines, msfconsole, python…), with tab completion and commands recalled from
history, and it is what keeps passwords out of the log: whatever you type at a prompt that does not
echo (sudo, ssh, su, `mysql -p`, `read -s`, also on the remote side) never appears on screen and is
never recorded. Full-screen programs (vim, less, htop, tmux) use the alternate screen and are
ignored. The feature can be turned off under Settings › Terminal.

### Chef

Operations on the left, the recipe in the middle, input and output on the right — the output is
recalculated on every change. Click an operation to add it as a step; steps have parameters
(delimiter, key, shift, regex, …), can be disabled, reordered or removed, and show the byte count
or the error after each step. Paste something unknown and the magic bar suggests what it looks
like (Base64, hex, URL-encoded, JWT, JSON, Unix time, …) — one click adds the decoder. **Use as
input** feeds the output back in for the next round; recipes can be saved by name. Everything runs
locally; nothing is sent anywhere. Besides the usual encodings, hashes, text and data operations
there are JWT decode / **sign** (HS256/384/512, none) / **verify**, PowerShell `-EncodedCommand`
encode / decode, Base58, double URL encoding, JSON string escaping, shell single-quoting, and a
**Units** category: data sizes (`1.5 GB` → MB, GiB, …) and durations (`90m`, `1h 30m`, `h:mm:ss`).

**Identify hash** (one hash or hash-bearing line per input line) names the likely algorithms with
the hashcat mode and john format, splits them into *likely* and *less likely*, and ends with a
ready-made `hashcat -m … / john --format=…` line. It understands more than bare digests: `hash:salt`
pairs (with the vBulletin/MyBB/Joomla/osCommerce salt lengths), `user:hash` and /etc/shadow lines,
pwdump/secretsdump lines (NT in field 4, LM in field 3, empty-password and disabled-LM hashes
pointed out), NetNTLMv1/v2 captures and Responder log lines, Kerberos (TGS-REP, AS-REP, pre-auth
for etypes 17/18/23), DCC2, Unix crypt (descrypt, bsdicrypt, md5crypt, bcrypt, sha256/sha512crypt,
yescrypt, Argon2, sunmd5, sha1crypt), PBKDF2 and scrypt notations, Django/phpass/Drupal/WordPress,
LDAP `{SSHA}`-style and AIX hashes, MySQL/PostgreSQL/MSSQL/Oracle/Sybase, Cisco (types 4/5/7/8/9,
ASA/PIX, whole `enable secret`/`password 7` configuration lines), Juniper `$9$`, FortiGate, Office,
PDF, ZIP/RAR/7z, KeePass, GPG, SSH keys, BitLocker, wallets, WPA, JWTs, Base64 digests, `0x`
prefixes, checksum lines and colon-separated fingerprints. **Cisco type 7 decode** and **Juniper $9$
decode** reverse those two obfuscations (the magic bar spots them too).

## Project layout

```
Package.swift              SwiftPM manifest (macOS 14+, Swift 5.9+)
build.sh                   builds and bundles Luik.app (signs with "Luik Local" when present)
scripts/make-signing-identity.sh  one-time local signing certificate, so macOS permissions survive rebuilds
Sources/Luik/
  main.swift               starts NSApplication
  AppDelegate.swift        menu bar item, main menu, hotkey, wiring of all modules
  HotKey.swift             global hotkey (Carbon RegisterEventHotKey, no extra permissions needed)
  HotKeyRecorder.swift     recorder field for choosing your own hotkey
  DropdownPanel.swift      the sliding panel (position, animation, handing focus back)
  RootView.swift           tab bar + settings
  Settings.swift           keys and defaults
  Storage.swift            JSON storage + autosave
  Terminal/                SwiftTerm sessions and tabs
  Notes/                   Markdown notes, renderer (MarkdownView) and the library sidebar
  Library/                 library store (collections of .md files), GitHub downloads and the sources sheet
  Snippets/                one-liners (multi-step, ordering, $RHOST/$RPORT/$RURL/$LHOST/$LPORT)
  Diagram/                 network diagrams: model and store, rendering, canvas and inspector, import/export
  Plan/                    test plans: model, built-in templates, store, tab and template editor
  Tools/                   Tools tab: version & end-of-life check (endoflife.date, GitHub releases), mail security (SPF/DKIM/DMARC via dig), reachability canary, public IP
  Shells/                  reverse shell generator (templates read from the library's cheat sheet)
  Targets/                 nmap/Nessus/nuclei/masscan parsers, tree model, import/export and UI
  KnowledgeBase/           xlsx/csv/json import, search index, catalogue download and UI
  Exploits/                Exploit-DB (searchsploit) database, smart search and commands
  Chef/                    CyberChef-style operations, recipe engine, hash identifier and UI
  Findings/                finding model, CVSS 3.1 calculator, store with report export, UI
  Engagements/             engagement store (per-engagement files, scope matcher) and manager UI
  Activity/                activity log store, typed-command capture and UI
  Palette/                 ⌘K search over everything
  Evidence/                screenshot evidence via screencapture, image annotator (blur / redact)
  UpdateCheck.swift        GitHub release check
Vendor/SwiftTerm/          SwiftTerm 1.11.2 (MIT) as source
Resources/AppIcon.iconset  app icon
knowledge-base/            downloadable knowledge bases (EN/NL) and the catalog.json the app reads
```

### Remote desktops and VMs (Windows App, Microsoft Remote Desktop, Parallels, VMware)

Luik's hotkey is system-wide: while it is registered, that key never reaches a remote desktop or
VM. If you want ⌘Esc (or whatever you chose) passed through there, enter the app's name under
Settings › General › **Pause hotkey in** (e.g. `Windows App, Remote Desktop`). While that app is
active the hotkey is paused; open Luik from the menu bar icon in the meantime. As soon as you
switch to another app the hotkey works again.

When hiding, Luik hands focus back to the app that was active before (macOS 14 "cooperative
activation"). If that fails, Luik withdraws itself so macOS activates the next app; otherwise that
app would get mouse input but no keyboard input.

## Troubleshooting

- **The hotkey does nothing**: macOS or another app probably owns the combination (for function
  keys: `fn`). Pick another hotkey via the menu bar icon › Settings.
- **Keyboard stops working in a remote desktop (mouse works)**: quit Luik for a moment (menu bar
  icon › Quit Luik). If it works again, add the remote desktop app's name under "Pause hotkey in"
  and use version 0.2 or newer (better focus hand-back). If it is also broken without Luik, look
  at "Secure Keyboard Entry" (Terminal/iTerm2 menu): with that enabled, remote desktop clients on
  macOS often get no keyboard input at all.
- **The panel does not appear over a full-screen app**: Luik uses a floating panel that is allowed
  over full-screen apps; if that fails, switch Spaces briefly.
- **macOS keeps asking for Screen Recording (evidence screenshots) although you granted it**: the
  permission is tied to the app's code signature, and an ad-hoc signature changes with every
  rebuild, so each `./build.sh --install` looks like a new app to macOS. Run
  `./scripts/make-signing-identity.sh` once: it creates a local "Luik Local" certificate that
  `build.sh` then uses, so the identity stays the same across builds. Rebuild, and in System
  Settings › Privacy & Security › Screen Recording remove the old Luik entry (−) and grant it once
  more. On macOS 15 a monthly "continue to allow" confirmation is normal for every screen-recording
  app. Downloads from the Releases page are ad-hoc signed and keep the old behaviour.
- **Build errors**: the code targets Swift 5.9+ and macOS 14+. Open an issue with the error message.
- **Starting over**: quit Luik and delete (or rename) `~/Library/Application Support/Luik/`.

## License

Luik is available under the [MIT License](LICENSE).

Luik bundles [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) by Miguel de Icaza (version
1.11.2, MIT License, with two small Luik-specific additions marked in the source) as source in
`Vendor/SwiftTerm/`; its license is in `Vendor/SwiftTerm/LICENSE`. The colour schemes use values
from the [dictionary-of-colour-combinations](https://github.com/mattdesl/dictionary-of-colour-combinations)
dataset by Matt DesLauriers (MIT License), digitised from Sanzo Wada's 1933 book.
