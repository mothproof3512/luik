# Knowledge bases

Ready-made knowledge bases for Luik's **Knowledge base** tab, and the catalogue the app downloads
them from. In Luik: Knowledge base tab → **Download** (also Tools › Download Knowledge Base… and
⌘K → "Download knowledge base"), pick a language, click **Import**.

| File | Language | Rows | Contents |
|---|---|---|---|
| `attack-vectors-knowledge-base_EN_1.0.xlsx` | English | 349 | Attack vectors and CVEs across web, API, internal/external network, Active Directory, cloud, mobile, wireless, social engineering, physical, endpoint and AI/LLM |
| `attack-vectors-knowledge-base_NL_1.0.xlsx` | Dutch | 349 | The same rows with Dutch report text |

Every row has an `ID` (`AV-WEB-01`, `CVE-…`), `Scope`, `Vector` (the title), `Category`,
`Kill_chain_phase`, `Severity_default`, `Description`, `Impact`, `Test_approach`, `Remediation`,
`Detection_note`, mappings to OWASP Top 10 2025, OWASP API Top 10 2023, WSTG, ASVS 5.0, MITRE
ATT&CK, CWE, PayloadsAllTheThings, OSCP+ modules and CISSP domains, and for CVE rows the CVSS
score/vector, affected and fixed versions, CISA KEV status and public-exploit status. The `Legend`
sheet in each workbook explains the columns and conventions; the `Changelog` sheet tracks changes.

In Luik, `Vector` becomes the title, `Scope`, `Severity_default` and `Kill_chain_phase` drive the
filters, and **Create finding** maps `Description`, `Impact`, `Remediation`, `References`,
`Test_approach` (as the starting evidence) and `CVSS_vector` to the finding's fields; every other
filled column is appended to the description.

## Hosting your own catalogue

Luik can download from any link: an `.xlsx`, `.csv`, `.tsv` or `.json` file on GitHub, GitLab, a
web server or a share (GitHub page links, `…/blob/…`, are turned into raw downloads
automatically), or a **catalogue** that lists several files. A catalogue is a `catalog.json`:

```json
{
  "name": "ACME pentest knowledge bases",
  "entries": [
    {
      "id": "acme-web",
      "name": "ACME web findings",
      "language": "English",
      "version": "2026.10",
      "file": "acme-web-findings.xlsx",
      "records": 120,
      "description": "Optional one-line description shown in the sheet."
    },
    {
      "id": "acme-infra",
      "name": "ACME infrastructure findings",
      "version": "2026.10",
      "file": "https://example.com/kb/infra.csv"
    }
  ]
}
```

- `id` identifies the entry across versions: when the imported knowledge base has the same `id`
  and a different `version`, the sheet offers **Update**.
- `file` is relative to the catalogue's own location, or an absolute URL. `language`, `records`
  and `description` are optional.
- Paste the catalogue's URL in the **Your own file or catalogue** field of the Download sheet, or
  put it in **Settings › Tools › Knowledge base catalogue** to make it the default list for your
  team. For a private GitHub repository, add a fine-grained personal access token with read access
  to the repository's contents in the sheet's token field; Luik sends it as an `Authorization`
  header and keeps it in your login keychain.

Imported knowledge bases live in `~/Library/Application Support/Luik/knowledgebase.json` and never
leave the Mac; nothing is sent anywhere except the download request itself.
