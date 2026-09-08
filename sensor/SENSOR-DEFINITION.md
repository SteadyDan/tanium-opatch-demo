# Sensor: Oracle Patch State

Console: Administration → Content → Sensors → Create Sensor

| Field | Value |
|---|---|
| Name | Oracle Patch State |
| Description | Orchestrator state for Oracle OPatch sequencing. Written by the "Oracle OPatch" packages. |
| Category | Oracle |
| Result type | Text |
| Max sensor age | **1 minute** (default is 15 min; the gates between steps need fresh answers) |
| Max strings | default |
| Delimiter | `\|` |
| Columns (in order) | `State`, `Patch ID`, `Last Exit Code`, `Last Updated` |
| Script — Linux | contents of `oracle_patch_state.sh`, script type **Shell** |
| Script — Solaris | identical file (when you add real Solaris endpoints, tick the platform and paste the same script) |

## Values you will see

| State | Meaning | Set by |
|---|---|---|
| `not_configured` | prep not run / state file absent | sensor default |
| `none` | prepped, nothing staged | prep_endpoint.sh |
| `staged` | payload verified and unpacked to `/u01/stage/<id>` | stage.sh |
| `prereq_ok` | conflict check passed | prereq.sh |
| `applied` | patch in lsinventory, DB back up | apply.sh |
| `rolled_back` | patch removed, DB back up | rollback.sh |
| `failed` | any step failed; `Last Exit Code` says why | fail() in lib.sh |

## Exit codes in the `Last Exit Code` column

| Code | Source | Meaning |
|---|---|---|
| 0 | — | success |
| 1 | OPatch | generic failure (DB still running, not run as oracle, patch not present) |
| 73 | OPatch | prerequisite / conflict check failed |
| 90 | orchestrator | step ran out of sequence (targeting mistake — state unchanged) |
| 91 | orchestrator | expected file missing (zip, sha256, staging dir, unzip binary) |
| 92 | orchestrator | payload checksum mismatch |
| 93 | orchestrator | database service would not stop or start |
| 94 | orchestrator | post-step verification against lsinventory failed |

## Useful questions

```
Get Oracle Patch State from all machines
Get Oracle Patch State from all machines with Oracle Patch State:State equals staged
Get Computer Name and Oracle Patch State from all machines with Oracle Patch State:State equals failed
```

The second form is the gate used by the action groups / playbook conditions.
