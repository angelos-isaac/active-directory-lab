# Detections

**Status: not yet implemented.** This directory is a placeholder for the detection engineering phase. See [`docs/08-logging-and-detection.md`](../docs/08-logging-and-detection.md) for the planned design.

The audit configuration these detections will depend on is complete and verified — advanced audit policy, command line process auditing, PowerShell script block logging, and object access auditing with SACLs. That work is documented in [`docs/06-group-policy.md`](../docs/06-group-policy.md) and [`docs/07-file-server-and-permissions.md`](../docs/07-file-server-and-permissions.md).

## Planned contents

| File | Contents |
|---|---|
| `local_rules.xml` | Rule source as deployed to `/var/ossec/etc/rules/` |
| `T1136.001-account-creation.md` | Telemetry, rule, alert, and tuning for account creation |
| `tuning-notes.md` | False positives encountered and how each was resolved |

## Verify before trusting a rule

Parent rule IDs and decoded field names differ between Wazuh versions. A rule with the wrong parent produces no alert and no error, so rules will be validated against live events with `sudo /var/ossec/bin/wazuh-logtest` before being recorded as working.
