"""Structured error codes for the probe-lean MCP server.

Every tool returns a plain dict on failure -- never a stack trace. The dict has
the shape ``{"error": <code>, "message": <human text>, "hint": <next step>?}``.
The codes are a closed set so agents can branch on them programmatically.
"""

from __future__ import annotations

# The closed set of machine-readable error codes (see specs/active/mcp-server.md).
BINARY_NOT_FOUND = "binary_not_found"
TOOLCHAIN_MISMATCH = "toolchain_mismatch"
BUILD_FAILED = "build_failed"
NO_OUTPUT = "no_output"
ATOM_NOT_FOUND = "atom_not_found"
AMBIGUOUS_OUTPUT = "ambiguous_output"
TIMEOUT = "timeout"
BAD_ARGS = "bad_args"

ERROR_CODES = frozenset(
    {
        BINARY_NOT_FOUND,
        TOOLCHAIN_MISMATCH,
        BUILD_FAILED,
        NO_OUTPUT,
        ATOM_NOT_FOUND,
        AMBIGUOUS_OUTPUT,
        TIMEOUT,
        BAD_ARGS,
    }
)


class ProbeError(Exception):
    """Raised by core helpers; carries a structured, agent-facing payload.

    Tool handlers catch this and return :meth:`to_dict` so the client sees a
    structured object instead of an exception.
    """

    def __init__(self, code: str, message: str, hint: str | None = None):
        assert code in ERROR_CODES, f"unknown error code: {code}"
        super().__init__(message)
        self.code = code
        self.message = message
        self.hint = hint

    def to_dict(self) -> dict:
        out = {"error": self.code, "message": self.message}
        if self.hint is not None:
            out["hint"] = self.hint
        return out
