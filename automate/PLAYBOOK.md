# Sequencing layer

Two ways to chain the four packages. Build the action-group version first (ten minutes, no module dependency), then the Automate playbook on top: the playbook is the story, the action groups are the safety net that proves the gates hold even without it.

## A. Sensor-gated action groups (works everywhere, Solaris included)

The sensor is the state machine; each scheduled action only targets endpoints in the state the previous step should have left.

| # | Action (package) | Target (question filter) | Reissue every |
|---|---|---|---|
| 1 | Oracle OPatch - 1 Stage | `Oracle Patch State:State equals none` | 5 min |
| 2 | Oracle OPatch - 2 Prereq | `Oracle Patch State:State equals staged` | 5 min |
| 3 | Oracle OPatch - 3 Apply | `Oracle Patch State:State equals prereq_ok` | 5 min |
| 4 | Oracle OPatch - 4 Rollback | `Oracle Patch State:State equals failed and Oracle Patch State:Last Exit Code does not equal 73` | 5 min (optional auto-remediate) |

Set all four up as scheduled actions in one action group with a 1–2 hour end time. A freshly prepped endpoint walks itself `none → staged → prereq_ok → applied` with no human in the loop, one reissue interval per hop. Because the sensor max age is 1 minute, the gate opens within a minute of each step finishing.

Talking points while it runs:

- Nothing is time-based. Step 3 fires because the endpoint *says* it is ready, not because a timer expired.
- Inject a conflict (`touch /u01/stage/12345678/FORCE_CONFLICT` before Prereq fires) and the endpoint parks at `failed|73`. Apply never targets it. The rollback action deliberately excludes 73 (there is nothing to roll back after a conflict) so the endpoint stays visible as needing a human.
- Fire Apply by hand at a `none` endpoint: it returns 90, state is unchanged. The scripts refuse to trust the console's targeting.

## B. Automate playbook

Block names differ slightly between Automate versions; each row names the capability, map it to the nearest block in your console.

```
Playbook: Oracle OPatch - Apply 12345678
Trigger:  manual (demo) — could equally be a schedule or a Connect/webhook event

 1  Deploy Action     Oracle OPatch - 1 Stage
                      targets: Oracle Patch State:State equals none
                      wait for action to complete (or 10 min)
 2  Ask Question      Get Computer Name and Oracle Patch State from all machines
                      with Oracle Patch State:Patch ID equals 12345678
 3  Condition         any rows where State equals failed ?
      yes → 3a Notify  (email / Slack / ServiceNow) "Stage failed on <computers>: rc <code>"
             → END
      no  → continue
 4  Deploy Action     Oracle OPatch - 2 Prereq
                      targets: Oracle Patch State:State equals staged
                      wait for completion
 5  Ask Question      as step 2
 6  Condition         any rows where State equals failed and Last Exit Code equals 73 ?
      yes → 6a Notify  "Patch conflict on <computers> — needs DBA review"
             → END  (nothing to roll back; endpoint parked at failed|73)
      no  → continue
 7  Deploy Action     Oracle OPatch - 3 Apply
                      targets: Oracle Patch State:State equals prereq_ok
                      wait for completion (set 60 min for a real patch)
 8  Ask Question      as step 2
 9  Condition         any rows where State equals failed ?
      yes → 9a Deploy Action  Oracle OPatch - 4 Rollback
                              targets: Oracle Patch State:State equals failed
             9b Notify        "Apply failed on <computers> (rc <code>); rolled back"
             → END
      no  → 10 Notify "Patch 12345678 applied on <n> endpoints" → END
```

Design notes worth saying out loud:

- The playbook never carries state itself. Every branch re-asks the endpoint, so a run that dies half-way can simply be re-run and picks up where the fleet actually is.
- The three failure branches map to three different owners: stage failure is a Tanium/infra problem (checksum, missing file), 73 is a DBA problem (conflict), apply failure is an incident (rolled back automatically, someone still needs to look).
- For ring deployments, wrap steps 1–10 in a loop over computer groups (pilot → wave 1 → wave 2) with a "failed count equals 0" condition between rings. Automate's deployment plan feature does this natively if you would rather show that than a hand-rolled loop.

## What this does *not* emulate

- Real OPatch runtime and locking (`opatch` can hold the OH lock for an hour; set realistic timeouts).
- Datapatch / SQL post-steps (`datapatch -verbose` after apply). Add a fifth package if the audience cares.
- RAC rolling patching across nodes — sequencing between endpoints rather than within one. The same sensor-gating pattern handles it (node 2 targets `node 1 applied`), but it needs a shared state source, usually Connect writing to a small database or the playbook holding the node order.
