# Detections

Custom Wazuh rules written against telemetry from this environment, with the tuning analysis behind them.

| File | Contents |
|---|---|
| [`local_rules.xml`](local_rules.xml) | Rule source as deployed to `/var/ossec/etc/rules/` on SIEM01 |
| [`tuning-notes.md`](tuning-notes.md) | False positive analysis and baselines |

Execution detail and evidence: [`docs/08-logging-and-detection.md`](../docs/08-logging-and-detection.md)

---

## Rules

| ID | Level | Technique | Detects |
|---|---|---|---|
| 100100 | 12 | T1136.001 | Local account creation via `net.exe` or `net1.exe` |

---

## Validate before trusting a rule

Two independent failure modes, and neither produces a useful error.

**Syntax errors prevent the manager from starting.** Validate first:

```bash
sudo /var/ossec/bin/wazuh-analysisd -t
```

Silence means the ruleset parsed.

**A syntactically valid rule can still match nothing.** Wazuh uses OS_Regex by default, not PCRE2. A pattern written with PCRE2 habits loads cleanly and never fires. Field names and `if_group` values are also version-specific.

The reliable way to write a rule is to read the shipped ruleset and copy how its authors do it:

```bash
sudo head -30 /var/ossec/ruleset/rules/0800-sysmon_id_1.xml
```

That file shows the correct group name, field paths, and the `type="pcre2"` attribute. Faster than guessing, and it is version-accurate by definition.

**And confirm the manager actually restarted:**

```bash
sudo systemctl status wazuh-manager --no-pager | head -5
```

An uptime in hours means the rule file was never re-read.
