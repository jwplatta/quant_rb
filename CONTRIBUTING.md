# Contributing

## Development setup

1. Install Ruby 3.1+ and Bundler.
2. Install dependencies:

```bash
bundle install
```

3. Run the active test suite to confirm the environment is working:

```bash
bundle exec rspec spec/quant_rb
```

## Workflow

1. Start from a focused branch named `feature/...`, `fix/...`, `chore/...`, `refactor/...`, `docs/...`, or `test/...`.
2. Keep changes targeted. Do not mix unrelated cleanup into the same branch.
3. Prefer adding work to `lib/quant_rb/`, `spec/quant_rb/`, `examples/`, and supporting docs. Treat `bots/` as legacy reference code unless the task is explicitly about migration.
4. Add or update specs for behavior changes.
5. Update the `Unreleased` section in [`CHANGELOG.md`](CHANGELOG.md) for user-visible gem changes. Skip changelog updates for internal-only refactors, tests, docs, or tooling.
6. Bump [`lib/quant_rb/version.rb`](lib/quant_rb/version.rb) only when cutting a release, and always pair that bump with a versioned changelog entry.
7. Use semantic versioning for releases: patch for backward-compatible fixes, minor for backward-compatible features, major for breaking changes.
8. Cut a release when `main` has stable user-visible changes worth publishing, or when a user-facing fix should ship immediately.
9. Run relevant checks before opening a pull request.
10. Use conventional commit messages, for example `feat: add synthetic chain interpolation` or `fix: handle missing option quote timestamps`.

## Running checks

Run the active test suite before opening a pull request:

```bash
bundle exec rspec spec/quant_rb
```

Run the full suite when changes may affect legacy reference code or shared project wiring:

```bash
bundle exec rspec
```

Run linting before opening a pull request:

```bash
bundle exec rubocop
```

Build the gem when changing packaging, versioning, or release-related files:

```bash
bundle exec rake build
```

## Project boundaries

- Keep active product work focused on the `quant_rb` gem.
- Treat `bots/` and other legacy `options_trader` artifacts as reference material slated for deletion.
- Prefer using local file-based market data from the configured data root instead of wiring new code directly to live APIs.
- Keep backtesting, scheduling, portfolio, data, and reporting concerns separated behind the existing `quant_rb` module boundaries.
- Keep generated outputs such as local backtest summaries and trade logs out of git.

## Pull requests

- Keep commits focused and intentional.
- Use conventional commit messages.
- Include tests for changes to engine flow, scheduling, portfolio behavior, data loading, synthetic chain generation, or reporting.
- Document any changes to public API, example usage, output format, or data layout in [`README.md`](README.md) or the relevant docs under [`doc/`](doc/).
