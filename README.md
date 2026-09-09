# Tanium ⇢ Oracle OPatch orchestration — lab kit

Emulates Tanium orchestrating Oracle OPatch on Solaris, using an Ubuntu VM and a stub `opatch` that honours the real CLI contract and exit codes (0 / 1 / 73). Everything on the Tanium side — remote-file packages, the state sensor, the sequencing — is the real mechanism, not a mock.

```
opatch-kit/
├── endpoint/   prep_endpoint.sh, opatch (stub), oracle-db-sim.service, reset_demo.sh
│   └── solaris/ prep_solaris.sh, oracle-db-sim.xml (SMF manifest), oracle-db-sim (method)
├── patch/      build_patch_zip.sh  → dist/p12345678_190000_Linux-x86-64.zip (+ .sha256)
├── packages/   lib.sh, stage.sh, prereq.sh, apply.sh, rollback.sh, PACKAGE-DEFINITIONS.md
├── sensor/     oracle_patch_state.sh, SENSOR-DEFINITION.md
├── automate/   PLAYBOOK.md  (action-group gating + Automate playbook)
└── test/       run_local.sh (23 checks, runs under dash)
```

All scripts are strict POSIX `sh` (shellcheck -s sh clean, tested under `dash`). `su - oracle -c`, service control and checksumming pick Linux or Solaris implementations at runtime, so the same files run on a Solaris 10 or 11 client unchanged.

## Setup order

**1. Ubuntu VM with Tanium Client.** Any 22.04/24.04 with `unzip` installed. Copy `endpoint/` across and run `sudo sh prep_endpoint.sh`. This creates `oracle`/`oinstall`, `ORACLE_HOME`, the stub `opatch`, and a running `oracle-db-sim.service`. Check: `su - oracle -c "opatch lsinventory"` shows *Interim patches (0)*.

**2. Build and host the payload.** `sh patch/build_patch_zip.sh` writes the zip and `.sha256` to `patch/dist/`. Tanium Cloud has to fetch them over public HTTPS, so:

- GitHub: push to a public repo, `gh release create v1 patch/dist/p12345678_*`, URLs are `https://github.com/<org>/<repo>/releases/download/v1/<file>`.
- Azure: `az storage blob upload --container patches --file <file> --account-name <acct>` on a container with anonymous blob read, or generate a SAS URL and paste that.

`curl -sI <url> | head -1` should return 200 before you go near the console.

**3. Sensor.** `sensor/SENSOR-DEFINITION.md`. Max age 1 minute matters.

**4. Packages.** `packages/PACKAGE-DEFINITIONS.md`. Save Stage last and watch the two remote files go *Cached*.

**5. Sequencing.** `automate/PLAYBOOK.md`. Action groups first, then the playbook.

## Demo script (15 minutes)

| Min | Do | Show |
|---|---|---|
| 0 | `Get Oracle Patch State from all machines` | `none\|0\|0\|…` — one row per prepped endpoint |
| 1 | Open the Stage package → Files | two remote URLs, status Cached, SHA-256 Tanium computed |
| 2 | Deploy Stage | action log: checksum expected/actual, unzip, `state -> staged` |
| 4 | Deploy Apply directly (skip Prereq) | exit 90 in action status; sensor still `staged`. Scripts enforce sequence regardless of who clicks what |
| 5 | Deploy Prereq, then Apply | `prereq_ok`, then `applied`. In the Apply log: service stop, OPatch banner, patching components, service start, lsinventory verify |
| 8 | `su - oracle -c "opatch lsinventory"` on the VM | patch 12345678 listed |
| 9 | Deploy Rollback | `rolled_back`, inventory empty, service up |
| 10 | Re-stage, then `sudo touch /u01/stage/12345678/FORCE_CONFLICT` on the VM, deploy Prereq | `failed\|12345678\|73\|…`. Apply is no longer targetable |
| 12 | Start the Automate playbook against a second, clean endpoint | it walks the steps and lands in the "applied" notify branch; the conflicted endpoint routes to the DBA-review branch |

Endpoint-side artefacts to open if asked: `/var/opt/oracle_patch/orchestrator.log` (every step, every state change), `/var/opt/oracle_patch/last_opatch_output.txt`, `$ORACLE_HOME/cfgtoollogs/opatch/opatch*.log` (stub writes real-looking OPatch logs).

## Testing without Tanium

`sudo sh test/run_local.sh` on any Ubuntu box or container runs the whole chain including the conflict and tampered-payload branches. Expected: `passed=23 failed=0`.

## Solaris notes (for when a real box turns up)

- Tanium runs packages through `/bin/sh` (ksh93 on Solaris 11). Nothing here needs bash.
- Service control switches to `svcadm disable -s` / `enable -s`; set `ORACLE_SERVICE=svc:/application/oracle/db:default` in the package command or `lib.sh`.
- Checksum switches to `digest -a sha256` automatically.
- Replace the stub with the real `$ORACLE_HOME/OPatch/opatch` and the four package scripts are production candidates, subject to timeouts and a datapatch step.

## Running the same demo on a Solaris test box

The stub, the payload and the four packages are identical. Only endpoint prep differs.

1. Tanium Client for Solaris installed and reporting (Solaris 10 or 11).
2. Get `endpoint/opatch` and the three files in `endpoint/solaris/` onto the box. Either
   `curl -sL https://github.com/SteadyDan/tanium-opatch-demo/archive/refs/heads/main.tar.gz | gunzip | tar xf -`
   or ship them as a Tanium package (`Oracle OPatch - 0 Prep Solaris`, four remote files, command
   `/bin/sh prep_solaris.sh`).
3. `sudo sh prep_solaris.sh` (or as root). It creates `oracle`/`oinstall`, `ORACLE_HOME`, installs the stub,
   imports `svc:/application/oracle-db-sim` into SMF and brings it online. Smoke test at the end.
4. Console: edit sensor `EPX - Oracle Patch State`, tick Solaris, paste the same script.
5. Nothing else changes. Packages call `/bin/sh`, `lib.sh` picks `svcadm`/`svcs` and `digest -a sha256` at run
   time, and the service defaults to `oracle-db-sim` (the SMF name) when `svcadm` is present. The playbook
   targets `State equals none`, so the Solaris box joins the next run on its own.

Solaris 10 is supported as-is: `/bin/sh` there is the 1989 Bourne shell, so every entry script starts with a
Bourne-syntax shim that re-execs itself under `/usr/xpg4/bin/sh` with `/usr/xpg4/bin` first on PATH (POSIX
`grep -q`, `id -un`). On Linux that path does not exist and the shim does nothing, so the package command stays
`/bin/sh <script>` everywhere. `unzip` is standard on Solaris 10 (`SUNWunzip`).

`reset_demo.sh` handles both platforms.
