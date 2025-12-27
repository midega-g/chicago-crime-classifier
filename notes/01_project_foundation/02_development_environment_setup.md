# Pre-commit Hooks Implementation

Pre-commit hooks transform the way data science teams maintain code quality by shifting from reactive detection of issues after commits to proactive enforcement before code enters the repository. In data science workflows, where reproducibility, deployment stability, and collaborative efficiency are paramount, these hooks act as automated guardians that run checks during the commit process, catching formatting errors, security vulnerabilities, and style violations early. This prevents minor issues from escalating into major problems, freeing developers to concentrate on core logic and methodologies rather than basic upkeep.

## Setting up Pre-commit

To set up, install pre-commit via your package manager, such as UV for data science environments.

```sh
uv add --group dev pre-commit
uv sync --group dev
```

Then activate the hooks.

```sh
pre-commit install
```

This integrates with Git. For existing codebases, run checks across all files.

```sh
pre-commit run --all-files
```

Observe that initial runs often uncover accumulated issues; automatic fixes from Black or isort may require re-staging and re-committing, while others need manual fixes. Performance can lag on large repos, so fail_fast helps, but consider selective hooks for speed. Update versions periodically.

```sh
pre-commit autoupdate
```

Review changes for compatibility. In workflows, commits trigger checks automatically.

```sh
git add .
git commit -m "Implement new feature"
```

If failing, resolve and retry; bypass rarely with `--no-verify`, but remediate promptly. For troubleshooting, clear caches.

```sh
pre-commit clean
```

Align dependencies in `pyproject.toml` with hook versions.

```toml
[dependency-groups]
dev = [
    "bandit>=1.8.6",
    "black>=25.9.0",
    "flake8>=7.3.0",
    "isort>=7.0.0",
    "mypy>=1.11.2",
    "pre-commit>=3.8.0",
    "pytest>=8.4.2",
]
```

Extend to CI/CD.

```sh
pre-commit run --all-files --show-diff-on-failure
```

Adopt gradually, starting with auto-fixers, and document for teams. Run specific hooks manually.

```sh
pre-commit run black
pre-commit run flake8
pre-commit run pytest-quick
```

Regular maintenance keeps the setup effective, yielding long-term benefits in code quality and productivity for data science endeavors.

## Breakdown of Pre-commit File

The heart of pre-commit implementation lies in the `.pre-commit-config.yaml` file, which orchestrates a suite of checks tailored for data science environments. It draws from various repositories to enforce standards across file hygiene, formatting, linting, security, and testing. Starting with basic file validations, the configuration incorporates hooks from the pre-commit/pre-commit-hooks repository to handle everyday consistency tasks.

### Foundational File Integrity

```yaml
- repo: https://github.com/pre-commit/pre-commit-hooks
  rev: v4.6.0
  hooks:
    - id: trailing-whitespace
    - id: end-of-file-fixer
    - id: check-yaml
    - id: check-json
    - id: check-toml
    - id: check-added-large-files
      args: ['--maxkb=10240'] # 10MB limit
    - id: check-merge-conflict
    - id: debug-statements
    - id: check-docstring-first
```

The code above ensures foundational file integrity by trimming trailing whitespace, standardizing file endings, validating syntax in YAML, JSON, and TOML files, limiting large file additions to 10MB to avoid repository bloat, detecting merge conflicts, spotting leftover debug statements, and confirming docstrings precede code in modules. These checks are essential in data science projects where diverse file types coexist, and inconsistencies can disrupt collaboration or automated pipelines.

### isort

Moving to import organization, the configuration employs isort to systematically arrange Python imports, reducing merge conflicts that often plague team-based development.

```yaml
- repo: https://github.com/pycqa/isort
  rev: 7.0.0
  hooks:
    - id: isort
      args: ["--profile", "black", "--length-sort"]
```

In the snippet above, isort aligns with the Black formatter's profile for seamless integration and sorts imports by length within groups, grouping standard, third-party, and local imports logically. This automation eliminates subjective debates on import order, promoting readability in scripts handling data loading or model training.

### Black

For consistent code styling, Black steps in as an opinionated formatter that applies uniform rules without room for variation.

```yaml
- repo: https://github.com/psf/black
  rev: 25.9.0
  hooks:
    - id: black
      language_version: python3.12
```

The code above specifies Python 3.12 compatibility and enforces an 88-character line limit, balancing compactness with clarity. In data science code, where complex expressions for data transformations or model definitions are common, Black's automatic reformatting ensures everyone adheres to the same aesthetic, minimizing diffs in version control.

### Flake

Linting follows to flag potential errors and style deviations, with Flake8 configured to complement the prior tools.

```yaml
- repo: https://github.com/pycqa/flake8
  rev: 7.3.0
  hooks:
    - id: flake8
      args: [
        "--max-line-length=88",
        "--extend-ignore=E203,W503",
        "--exclude=.git,__pycache__,build,dist,.venv"
      ]
```

Here, the arguments match Black's line length, ignore codes that clash with its formatting, and skip irrelevant directories like caches or virtual environments. This prevents noise from non-source files, allowing focus on genuine issues in production code, such as unused variables in analysis scripts.

### Bandit

Security remains a priority, addressed through Bandit, which automatically scans Python code for common security vulnerabilities such as hardcoded secrets, insecure function usage, or risky cryptographic practices—issues that can be especially dangerous in data science pipelines handling sensitive data or external API integrations.

```yaml
- repo: https://github.com/PyCQA/bandit
  rev: 1.8.6
  hooks:
    - id: bandit
      args: ["-r", ".", "-f", "json"]
      exclude: ^(tests/|scripts/extract_sample_data\.py)$
```

The configuration above enables recursive scanning (`-r`) starting from the project root (`.`), ensuring Bandit processes all relevant Python files passed by pre-commit during the commit stage. Output is formatted in JSON for structured parsing in CI environments, while the `exclude` pattern skips the test suite and a specific utility script (`scripts/extract_sample_data.py`) where intentional insecure patterns may appear for demonstration purposes.

Initially, a common error occurs when Bandit receives individual file paths (e.g., `scripts/extract_data.py`) alongside the `-r` flag, which expects directory targets. This mismatch triggers a usage error and halts the commit. The fix lies in removing hardcoded paths like `src/` from the `args` and instead letting pre-commit naturally pass changed files to Bandit. When a directory is among the staged changes, `-r` applies correctly; when only individual files are present, Bandit scans them directly without conflict. Additionally, explicitly excluding non-production scripts prevents false positives from tools or sample code, maintaining focus on production-grade security in core modules and pipelines. This adaptive approach ensures robust vulnerability detection without interrupting development flow.

### MyPy

Type safety is enhanced via MyPy for static analysis.

```yaml
- repo: https://github.com/pre-commit/mirrors-mypy
  rev: v1.11.2
  hooks:
    - id: mypy
      additional_dependencies: [types-requests]
      args: [--ignore-missing-imports]
      exclude: ^(tests/|scripts/)
```

This setup adds dependencies for typed libraries, ignores missing import types, and skips tests and scripts. It helps detect type mismatches early in model-building code, improving reliability in larger projects.

### Custom Checks

Custom checks round out the setup with local hooks tailored to project-specific needs, such as rapid unit testing during development. A key example is the `pytest-quick` hook, which executes a focused subset of critical tests to catch regressions early without the overhead of a full test suite.

```yaml
- repo: local
  hooks:
    - id: pytest-quick
      name: pytest-quick
      entry: pytest
      language: system
      pass_filenames: false
      args: [
        "tests/test_config.py",
        "tests/test_data_loader.py",
        "-v",
        "--tb=short",
        "--maxfail=3"
      ]
      files: ^(src/|tests/).*\.py$
      env:
        PYTHONPATH: src
```

The hook above triggers only when Python files in `src/` or `tests/` are modified, running verbose (`-v`) tests on `test_config.py` and `test_data_loader.py` with concise tracebacks (`--tb=short`) and halting after three failures (`--maxfail=3`). This ensures immediate feedback on core functionality—like configuration loading and data ingestion—without delaying commits.

However, a common issue arises: while running `pytest` directly from the terminal works (using your active conda or uv environment where the `chicago_crimes` package is accessible), the pre-commit hook may fail with `ModuleNotFoundError: No module named 'chicago_crimes'`. This occurs because pre-commit executes hooks in an isolated environment that does not automatically include your local package, even if it's importable in your shell.

The root cause is that test modules import from the package using absolute paths (e.g., `from chicago_crimes.config import ...`), but the package isn't installed or discoverable in pre-commit's temporary runtime context. To resolve this, ensure the package is installed in development mode:

```sh
uv pip install -e .
```

This creates an editable install, linking the `src/` directory into the environment's import path. Then, explicitly expose the source directory to the hook via the `PYTHONPATH` environment variable, as shown in the `env` field above. By setting `PYTHONPATH: src`, Python can locate the `chicago_crimes` package (assuming a `src/chicago_crimes/` layout) during test discovery and execution, eliminating import errors.

With this adjustment, the `pytest-quick` hook reliably passes both locally and in CI, maintaining fast feedback while respecting pre-commit’s isolation principles. This pattern is especially valuable in data science projects where early validation of data pipelines and configurations prevents downstream failures in training or inference workflows.

Global settings finalize the config.

```yaml
default_stages: [pre-commit]
fail_fast: true
```

These ensure hooks run pre-commit and halt on the first failure for efficiency.
