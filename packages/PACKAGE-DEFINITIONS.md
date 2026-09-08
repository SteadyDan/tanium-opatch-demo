# Package definitions

Console: Administration → Content → Packages → Create Package. Four packages, one per step.
All run as root under the Tanium Client; the scripts hop to `oracle` themselves.

Common settings for every package:

| Field | Value |
|---|---|
| Content set | Oracle (create it, or use Default for the lab) |
| Command timeout | 600 s (apply sleeps a few seconds; real OPatch would need 30–60 min) |
| Download timeout | 900 s (only matters for Stage, which carries the zip) |
| Command | `/bin/sh <script>.sh 12345678` — `/bin/sh`, not bash, so it is the same command on Solaris |
| Verification | tick **Verify**, query `Oracle Patch State:State equals <expected>` — see each package |
| Verification expiry | 10 minutes |
| Platform | Linux (add Solaris later; nothing changes) |

Package files are downloaded to `<client>/Downloads/Action_<n>/` and the command runs there, which is why every script does `. "$(dirname "$0")/lib.sh"` and expects the zip in cwd.

---

## 1. Oracle OPatch - 1 Stage

| Field | Value |
|---|---|
| Command | `/bin/sh stage.sh 12345678` |
| Local files | `stage.sh`, `lib.sh` |
| Remote file 1 | **Add file → Remote file**, URL `https://github.com/SteadyDan/tanium-opatch-demo/releases/download/opatch-demo-v1/p12345678_190000_Linux-x86-64.zip`, check for update: *Never* (or every 24 h if you want to show re-fetch) |
| Remote file 2 | same, URL `https://github.com/SteadyDan/tanium-opatch-demo/releases/download/opatch-demo-v1/p12345678_190000_Linux-x86-64.zip.sha256` |
| Verification query | `Oracle Patch State:State equals staged` |

What happens: Tanium Cloud fetches both remote files when you save the package (watch the file status turn from *Downloading* to *Cached*). On action, the client receives them via the peer cache; the script re-verifies the SHA-256 on the endpoint, unpacks to `/u01/stage/12345678`, hands ownership to `oracle`, writes `staged`.

Talking point: this is exactly the production shape. Tanium cannot authenticate to My Oracle Support, so in real life the zip lives on an internal artefact repo and Tanium pulls from there. The endpoint never needs outbound internet.

## 2. Oracle OPatch - 2 Prereq

| Field | Value |
|---|---|
| Command | `/bin/sh prereq.sh 12345678` |
| Local files | `prereq.sh`, `lib.sh` |
| Verification query | `Oracle Patch State:State equals prereq_ok` |

Refuses to run (rc 90) unless state is `staged`. Runs `opatch prereq CheckConflictAgainstOHWithDetail -ph ./` as `oracle`. Exit 73 from OPatch lands in the sensor as `failed|12345678|73|…`.

## 3. Oracle OPatch - 3 Apply

| Field | Value |
|---|---|
| Command | `/bin/sh apply.sh 12345678` |
| Local files | `apply.sh`, `lib.sh` |
| Verification query | `Oracle Patch State:State equals applied` |

Refuses unless `prereq_ok`. Stops the DB service, runs `opatch apply -silent`, restarts the service (trap guarantees this on any exit path), then verifies the patch is in `lsinventory` before it will write `applied`. If you skip the stop, the stub — like the real thing — refuses with exit 1 because the instance is up.

## 4. Oracle OPatch - 4 Rollback

| Field | Value |
|---|---|
| Command | `/bin/sh rollback.sh 12345678` |
| Local files | `rollback.sh`, `lib.sh` |
| Verification query | `Oracle Patch State:State equals rolled_back` |

Runs from `applied` (planned) or `failed` (remediation branch). If the patch was never applied it says so and still moves the endpoint to `rolled_back`, so the playbook has a clean terminal state either way.

---

## Optional: Oracle OPatch - 0 Prep Endpoint

Push `prep_endpoint.sh`, `opatch`, `oracle-db-sim.service` as a package with command `/bin/sh prep_endpoint.sh` to build the fake Oracle box on any Ubuntu client in one action. Verification: `Oracle Patch State:State equals none`.

## Parameterising the patch ID

The `12345678` on each command line can be a package parameter (`||patch_id||`) so the same four packages serve any patch. The zip file name in Stage is fixed per package though, so in practice you would keep one Stage package per patch and share Prereq/Apply/Rollback. Left hard-coded here to keep the demo readable.
