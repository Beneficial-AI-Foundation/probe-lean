# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Spec-Driven Development Workflow

This project uses spec-driven development. Follow this workflow:

### When the user asks you to implement a feature:

1. **Check for a spec first**: Look in `specs/active/` for a spec file
2. **If no spec exists**: Ask the user to write one, or offer to draft one together
3. **If spec exists**: Read it completely before proceeding
4. **Enter plan mode**: Create an implementation plan based on the spec
5. **Wait for approval**: Do not implement until the user approves the plan
6. **Implement**: Follow the spec strictly - do not add unrequested features

### When reviewing or drafting specs:

- Ensure requirements are testable and unambiguous
- Identify missing edge cases
- Flag any contradictions or unclear points
- Keep scope minimal - specs should describe one coherent feature

### Spec file locations:

- `specs/TEMPLATE.md` - Template for new specs
- `specs/active/` - Specs currently being worked on
- `specs/done/` - Completed specs (reference only)

## Documentation

- **README.md must be updated** with every new feature or command
- Include usage examples and option descriptions

## Commands

```bash
lake build                # Build the project
lake build tests          # Build tests
.lake/build/bin/tests     # Run tests
probe-lean atomize <PATH> # Analyze a Lean project
```

## Testing

- Tests are in `Tests/Main.lean`
- **Tests must be added** for each new feature
- Run tests before committing
- All tests must pass before merging

## Architecture

[To be filled in as the project develops]
