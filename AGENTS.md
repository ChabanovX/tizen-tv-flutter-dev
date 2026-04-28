# AGENTS.md

## Project goal

The current goal is to run the Flutter/Tizen project on the Samsung TV Tizen emulator.

More specifically, we are trying to reach this state:

```text
flutter-tizen run -d emulator-26101
```

successfully builds, installs, and launches the app on the Samsung/Tizen TV emulator.

## Important current context

The emulator can already boot far enough for SDB:

```text
sdb devices
# emulator-26101    device    Tizen_TV_HD1080
```

`flutter-tizen devices` can see the emulator as a Tizen TV target.

The major reverse-engineering finding so far is that guest-side `sdbd` connects outbound to the host SDB server through SLIRP, and it needs this kernel cmdline parameter:

```text
host_ip=10.0.2.2
```

Relevant cmdline parameters discovered so far:

```text
vm_name=Tizen_TV_HD1080
host_ip=10.0.2.2
sdb_port=26100
ip=10.0.2.15::10.0.2.2:255.255.255.0::eth0:off
```

The current practical blocker is not SDB visibility anymore. The current practical blocker is app installation/signing:

```text
install failed[118, -12], reason: Check certificate error
```

The next useful milestone is creating a valid Samsung TV/Tizen signing profile, rebuilding the `.tpk`, and retrying:

```bash
flutter-tizen run -d emulator-26101
```

## Required behavior for agents

When working on this repository, maintain `docs/FINDINGS.md` as cross-agent memory for this goal.

Only modify `docs/FINDINGS.md` when a finding is both:

1. **New** — it is not already recorded in `docs/FINDINGS.md`.
2. **Useful** — it can help another model/developer complete the goal of running the project through the Samsung emulator.

Do **not** add notes that are only conversational, speculative without evidence, or already obvious from existing findings.

Do **not** rewrite the whole file unless the user explicitly asks for a cleanup. Prefer appending a new finding at the bottom.

Do **not** remove existing findings unless they are proven wrong and actively misleading. If correcting a previous finding, append a correction entry that clearly says what was wrong and what replaced it.

## What counts as a useful finding

Useful findings include:

- a command that successfully advances the emulator/signing/deploy flow;
- a command that failed in a non-obvious way and explains a blocker;
- a required environment variable, path, package, certificate profile, or SDK component;
- a discovered relationship between Samsung Certificate Manager, Tizen Studio, VSCode Tizen Extension, `sdb`, `flutter-tizen`, or `.tpk` signing;
- a confirmed limitation of the Apple Silicon emulator workaround;
- a verified fix for `Check certificate error`;
- evidence that install, launch, rendering, input, or debugging works or does not work;
- a reproducible script or command sequence that another agent can use.

Not useful enough:

- “I tried something and it did not work” without command/output/context;
- generic documentation summaries not connected to this project;
- guesses without labels;
- duplicate restatements of existing findings;
- personal commentary.

## Required format for modifying `docs/FINDINGS.md`

Append each new finding as a standalone Markdown section.

Use this exact metadata format at the top of every new entry:

```markdown
---
MODEL_NAME = <model name>
FINDING_DATE = <YYYY-MM-DD HH:mm timezone>

### <short finding title>

**Status:** verified | failed | hypothesis | partial

**Finding:** <one concise paragraph explaining the new information>

**Evidence:**
<paste the relevant command/output/log excerpt here>

**Why it matters:** <explain how this helps another model complete the Samsung emulator goal>

**Next action:** <the most practical next command or investigation step>
```

### Example

```markdown
---

MODEL_NAME = Claude Opus 4.7
FINDING_DATE = 2026-04-28 10:30 Europe/Amsterdam

### Samsung TV certificate profile is required for emulator install

**Status:** verified

**Finding:** The `.tpk` can be built and pushed to `emulator-26101`, but installation fails when the active signing profile uses a generic Tizen developer certificate plus the default public distributor certificate. The Samsung TV emulator rejects this chain during package install.

**Evidence:**
install failed[118, -12], reason: Check certificate error


**Why it matters:** Future agents should not continue debugging SDB or QEMU for this error. The next blocker is signing/certificate profile setup.

**Next action:** Install Samsung Certificate Extension / Samsung TV certificate tooling, create a Samsung TV profile through the Samsung account flow, rebuild the `.tpk`, and retry `flutter-tizen run -d emulator-26101`.
```

## Before adding a finding

Before editing `docs/FINDINGS.md`, do this checklist:

1. Read the existing `docs/FINDINGS.md`.
2. Search inside it for the same command, error message, certificate term, package name, or script name.
3. If the information is already present, do not add a duplicate.
4. If the new information refines an existing finding, append a short correction/refinement instead of rewriting history.
5. Include enough command/output evidence that another agent can trust and reproduce the finding.

## Preferred evidence style

Prefer exact command/output snippets:

```bash
sdb devices
flutter-tizen devices
flutter-tizen run -d emulator-26101
tizen certificate --help
tizen security-profiles list
```

Prefer short excerpts over huge logs. Include only the lines needed to prove the finding.

If a finding is a hypothesis, mark it explicitly:

```markdown
**Status:** hypothesis
```

and explain what command would verify or falsify it.

## Safety and scope

The emulator workaround may rely on local scripts and local SDK paths. Do not assume paths are universal.

If referencing a local helper such as:

```bash
/tmp/tizen-utm/start-tizen-emulator.sh
```

make clear whether it exists on the current machine and whether it is reusable or only a local convenience.

Do not run destructive cleanup commands such as `rm -rf`, SDK removal, certificate deletion, or profile deletion unless the user explicitly asks for that operation.

Do not modify signing profiles, certificates, or keystores without first preserving enough information for rollback.
