# GDScript quality gates

## Scope

The repository uses `gdtoolkit` for GDScript linting and formatting:

- `.gdlintrc`: lint rules, maximum line length 100, maximum five function arguments.
- `gdformatrc`: formatter line length aligned to 100.
- CI currently enforces linting on the newly added combat regression test while the existing
  repository-wide lint baseline is triaged. The first full-repository run reported 202 findings,
  including existing ordering, line-length, unused-argument, and argument-count violations.
- Python tools are checked with Flake8 under Python 3.10. CI currently gates critical syntax and
  undefined-name classes (`E9,F63,F7,F82`); existing formatting/style debt is not a blocking gate.

## Commands

Install the tools in a Python 3.10 virtual environment:

```bash
python -m pip install "gdtoolkit>=4.3,<5" flake8
gdlint scripts/ tests/ scenes/
gdformat --check scripts/ tests/ scenes/
flake8 tools --count --select=E9,F63,F7,F82 --statistics
```

The full-repository GDScript command is an audit command until the existing baseline is remediated;
it is not the current CI gate. To format deliberately, review the working tree first, then run
`gdformat scripts/ tests/ scenes/` and inspect `git diff`. Do not auto-format unrelated files in
a review-sensitive change.

## Rule accuracy and limits

The supported gdlint rule is `function-arguments-number`, not `max-function-arguments`.
gdtoolkit does not provide a general unused-local-variable rule or an `unreachable-code` rule in
its standard gdlint configuration. It does provide `unused-argument`. Do not claim those
unsupported checks are enforced by gdlint; use Godot's parser/static diagnostics or a separate
analyzer if those checks become a requirement.

The `disable` list is intentionally empty. Test code is not exempted from correctness rules.
If test-specific complexity exceptions are later needed, use a separately validated configuration
file and confirm the installed gdtoolkit CLI's configuration options before adding command flags.
Do not assume `--disable max-function-arguments` is valid.

## Combat regression test

Run the combat mechanics test in the Godot scene tree so 3D nodes have a normal scene context:

```bash
godot --headless --path . res://tests/network_combat_mechanics_test.tscn
```

The test checks normal, zero, negative and lethal damage; HP clamping; death state; attacker
identity; and duplicate death-event prevention. It complements, rather than replaces, the existing
network combat smoke and loopback tests.

## Security reminders for ENet

- Treat clients as untrusted. The server must validate movement, cooldowns, range, damage, ownership,
  and all gameplay state transitions.
- Never accept client-provided damage or health as authoritative state.
- Keep RPC sender checks and server-side checks even when the UI disables invalid actions.
- Test timeout, disconnect, duplicate RPC, malformed values, reconnect, and unauthorized peer cases.
