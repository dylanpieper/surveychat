# surveychat

## Tests

The package has two kinds of tests.

| Kind | Folder | Model | Runs in CI |
|----|----|----|----|
| Unit tests | `tests/testthat/` | None. `fake_chat()` in `helper.R` gives scripted replies. | Yes, in `R-CMD-check.yaml` |
| Live checks | `tests/live/` | Claude Haiku (`anthropic/claude-haiku-4-5`) | No |

### Unit tests

The unit tests check the logic of the package: the spec, the form
values, the engine, the server, and the database. They use no model and
no API key. Snapshot tests need `NOT_CRAN=true`.

Run them from the package root with `devtools::test()` and
`NOT_CRAN=true`.

### Live checks

The live checks test what only a real model can show. A unit test
scripts the model reply, so it cannot catch a change in model behavior.
The live checks cover these behaviors:

- A full run of the workshop example writes the right rows to a SQLite
  file.
  - Each answer is stored in its stored form, such as a multi-select as
    JSON.
  - An early answer, a retry, and an adaptive question each get the
    right row.
  - The answers that later prompts use are the same as the answers in
    the file.
  - A relative date reply is written to the file as `YYYY-MM-DD`.
- A vague reply to a yes or no question, such as “maybe”, is not valid.
- A date reply becomes `YYYY-MM-DD`, also a relative date such as “next
  Friday”.
- A free reply maps to an enum value.
- One reply answers a later question early.
- A reply that breaks the `valid` rule gets a retry hint.
- A reply that builds on an earlier answer is valid, and an off-topic
  reply is not.
- An adaptive question is skipped when the answers already cover it, and
  asked when they do not.
- The closing line of the workshop example is short, has no thanks, and
  asks nothing.
- The intro of the workshop example is short and asks nothing.
- When the experience question was skipped, the workshop intro does not
  mention experience or say that the user gave no answer.
- An adaptive question does not list examples or name tools, unless its
  prompt asks for them.

Requirements:

- `ANTHROPIC_API_KEY` in `~/.Renviron`. Without it, each check skips.
- The suggested packages of the package, and devtools.

Run the checks from the package root:

``` sh
Rscript tests/live/run.R
```

Each run makes about 30 small calls to Claude Haiku. Run the checks
after a change to a prompt, a schema, or the model, and before a
release. `.Rbuildignore` leaves `tests/live/` out of the package build,
so `R CMD check` and CI do not run it.
