/-
  Internal sorry detection logic.
  Pure functions for parsing sorry warnings and matching them to atoms.
  Used by the combined Verify command.
-/
import Lean
import ProbeLean.Types
import ProbeLean.Analysis

namespace ProbeLean

open Lean

/-- A parsed sorry warning from Lean output -/
structure SorryWarning where
  filePath : String
  line : Nat
  column : Nat
  message : String
  deriving Repr, BEq

/-- Parse a single line of Lean output for sorry warnings -/
def parseSorryWarning (line : String) : Option SorryWarning := do
  if !containsSubstring line "sorry" then none

  let trimmed := line.trimAscii.toString
  if !trimmed.startsWith "warning: " then none

  let rest := (trimmed.drop 9).toString

  let parts := rest.splitOn ": "
  if parts.length < 2 then none

  let message := parts.getLast!
  let locationParts := parts.dropLast

  let locationStr := String.intercalate ": " locationParts

  let locParts := locationStr.splitOn ":"
  if locParts.length < 3 then none

  let filePathParts := locParts.dropLast.dropLast
  let filePath := String.intercalate ":" filePathParts

  let lineIdx := locParts.length - 2
  let colIdx := locParts.length - 1
  let lineStr := locParts[lineIdx]!
  let colStr := locParts[colIdx]!

  let lineNum ← String.toNat? lineStr
  let colNum ← String.toNat? colStr

  some {
    filePath := filePath
    line := lineNum
    column := colNum
    message := message.trimAscii.toString
  }

/-- Parse all sorry warnings from build output -/
def parseSorryWarnings (output : String) : Array SorryWarning :=
  let lines := output.splitOn "\n"
  lines.filterMap parseSorryWarning |>.toArray

/-- Normalize a file path by removing leading ./ and extracting filename -/
def normalizePathForMatch (path : String) : String :=
  let cleaned := path.replace "././" ""
  let parts := cleaned.splitOn "/"
  parts[parts.length - 1]!

/-- Check if two file paths refer to the same file -/
def pathsMatch (path1 : String) (path2 : String) : Bool :=
  path1 == path2 ||
  path1.endsWith path2 ||
  path2.endsWith path1 ||
  normalizePathForMatch path1 == normalizePathForMatch path2

/-- Check if a sorry warning falls within a declaration's line range -/
def sorryInDeclaration (warning : SorryWarning) (atom : Atom) : Bool :=
  if !pathsMatch warning.filePath atom.codePath then false
  else
    match atom.codeText with
    | none => false
    | some range =>
      warning.line >= range.linesStart && warning.line <= range.linesEnd

/-- Find all sorries for a given atom -/
def findSorriesForAtom (warnings : Array SorryWarning) (atom : Atom) : Array SorryInfo :=
  warnings.filterMap fun w =>
    if sorryInDeclaration w atom then
      some { line := w.line, message := w.message }
    else
      none

/-- Convert an atom and its sorries to a ProofEntry -/
def atomToProofEntry (atom : Atom) (sorries : Array SorryInfo) : ProofEntry :=
  let verified := sorries.isEmpty
  let status := if verified then VerifyStatus.success else VerifyStatus.sorries
  let codeLine := match atom.codeText with
    | some range => range.linesStart
    | none => 0
  {
    verified := verified
    status := status
    codePath := atom.codePath
    codeLine := codeLine
    sorries := sorries
  }

end ProbeLean
