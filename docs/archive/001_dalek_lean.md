# How Functions and Statuses are Computed

## Data Flow Overview

```
Rust Source Code (curve25519-dalek/)
       ↓
   [Aeneas Extraction]
       ↓
Lean Code (Curve25519Dalek/Funs.lean)
       ↓
   [lake exe syncstatus]
       ↓
functions.json + status.csv
       ↓
   [VitePress Build]
       ↓
GitHub Pages Site
```

## Step 1: Aeneas Extraction (Rust → Lean)

Aeneas extracts Rust functions to Lean definitions with docstrings containing metadata:

```lean
/-- [curve25519_dalek::backend::serial::...]: Source: 'curve25519-dalek/src/backend/serial/u64/field.rs', lines X:Y-A:B -/
def function_name := ...
```

## Step 2: `syncstatus` Command (`Utils/SyncStatus.lean`)

Run via `lake exe syncstatus`:

1. **Loads the Lean environment** from `Curve25519Dalek` module
2. **Enumerates all definitions** from `Curve25519Dalek.Funs` module (`Utils/Lib/ListFuns.lean:86-96`)
3. **Parses docstrings** to extract (`Utils/Lib/Docstring.lean`):
   - `rust_name`: Original Rust function path
   - `source`: Rust source file path
   - `lines`: Line numbers in Rust source
4. **Computes dependencies** by analyzing the Lean expression tree (`Utils/Lib/Analysis.lean:46-51`)
5. **Determines verification status** (`Utils/Lib/Analysis.lean:57-75`):
   - **`specified`**: Does a `{name}_spec` theorem exist?
   - **`verified`**: Does the spec theorem exist AND contain no `sorry`?
   - **`fully_verified`**: Is it verified AND all transitive dependencies verified?

## Step 3: Output Files

### `functions.json`

Contains all functions with:
- `lean_name`, `rust_name`, `source`, `lines`
- `dependencies` (filtered to relevant functions)
- `is_relevant`, `is_hidden`, `is_extraction_artifact`
- `specified`, `verified`, `fully_verified`
- `spec_file`, `spec_statement`, `spec_docstring`

### `status.csv`

A subset (excluding hidden/artifacts) for manual tracking with additional columns like `notes` and `ai-proveable`.

## Step 4: VitePress Data Loaders

- **`site/.vitepress/data/deps.data.ts`**: Reads `functions.json`, adds computed `dependents` field
- **`site/.vitepress/data/status.data.ts`**: Reads `status.csv` for statistics
- **`site/.vitepress/data/progress.data.ts`**: Reads `status.csv` from git history for progress tracking over time

## Key Files

| File | Purpose |
|------|---------|
| `Utils/SyncStatus.lean` | Main orchestration |
| `Utils/Lib/ListFuns.lean` | Function enumeration & filtering |
| `Utils/Lib/Analysis.lean` | Dependency & verification analysis |
| `Utils/Lib/Docstring.lean` | Parses Aeneas docstrings for Rust metadata |
| `Utils/Config.lean` | Configuration (hidden functions, excluded prefixes) |

## GitHub Pages Deployment

The site is deployed via `.github/workflows/deploy-docs.yml`:

1. Triggers on push to `master`, issue events, PR events, or manual dispatch
2. Runs `npm run docs:rust` to build Rust documentation
3. Runs `npm run docs:build` to build VitePress site from `site/` directory
4. Deploys `site/.vitepress/dist` to GitHub Pages
