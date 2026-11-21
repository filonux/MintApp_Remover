# Contributing

Thanks for your interest. Here are the basics:

## Reporting a bug or suggesting an improvement

Open an issue — there is a template for each case. To report a security problem, do not open an issue: follow [SECURITY.md](SECURITY.md).

## Submitting a change

1. Fork the repository and create a branch from the latest version.
2. Test your change with `bash tests/run_all.sh` and `bash tests/lint.sh`: they are the core of the CI and they never touch your real system. To run only some suites, name them (`bash tests/run_all.sh clean`; `--list` shows them). The linter needs ShellCheck 0.11.0 (`pip install shellcheck-py==0.11.0.1`).
3. Add or adjust the tests that cover your change, in the suite of the area it touches.
4. Open the pull request — the template guides you on what to include.

## Working with the tests

They are what lets you change the script and see at once what moved.

- `bash tests/run_all.sh --list` names each suite and the area it checks; `-v` prints every check, and each label states a behavior of the program.
- A failing check shows what it expected and what it got. Either the change broke something, or the behavior changed on purpose: then update that check in the same pull request.
- New behavior brings a check in the suite of its area; a bug fix brings a check that fails without the fix.
- To see whether a check really protects something, `python3 tests/mutate.py` and `python3 tests/faults.py` break the program on purpose, one change at a time, and list the changes that no check notices (their headers say how to run them).
- A case that needs a tool you do not have (`zenity`, `Xvfb`, `rpm`, `dnf`, `pacman`, `zypper`...) is skipped and says why. The CI installs them, and also repeats the suites on Debian, Ubuntu and a real `bash` 4.3.

## Code style

- Bash with `set -uo pipefail`, double quotes around expansions, `--` before paths that may start with `-`.
- Bash 4.3 is the minimum and the CI runs it: no features of 4.4 or later, and an array that may be empty is expanded as `"${a[@]+"${a[@]}"}"`.
- Every text shown to the user goes in both languages: `MSG_ES` and `MSG_EN`, and `APP_NAME_*` and `APP_DESC_*` for the application catalog. `tests/test_i18n.py` checks that the tables match.
- No trailing whitespace in `script/` or `tests/`: the CI checks it.
- Comments only where they explain a non-obvious why, not to repeat what the code already says.
- If the change touches icons, `.desktop` files or desktop paths: it is mainly tested on Cinnamon, so say in the PR whether it could affect other environments.
