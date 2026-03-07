/-
  CLI entry point for probe-lean.
  Two commands: verify (combined atomize+specify+sorry detection) and view (molecules output).
-/
import Cli
import ProbeLean.Verify
import ProbeLean.View

open Cli
open ProbeLean

/-- Run the verify command -/
def runVerify (parsed : Parsed) : IO UInt32 := do
  let projectPath := parsed.positionalArg! "projectPath" |>.as! String
  let outputPath := parsed.flag? "output" |>.map (·.as! String) |>.map System.FilePath.mk
  let moduleFilter := parsed.flag? "module" |>.map (·.as! String)
  let skipVerify := parsed.hasFlag "skip-verify"
  let skipBuild := parsed.hasFlag "skip-build"
  let fromFile := parsed.flag? "from-file" |>.map (·.as! String) |>.map System.FilePath.mk

  let config : VerifyConfig := {
    projectPath := projectPath
    outputPath := outputPath
    moduleFilter := moduleFilter
    skipVerify := skipVerify
    skipBuild := skipBuild
    fromFile := fromFile
  }

  runVerifyInProject config

/-- The verify subcommand -/
def verifyCmd : Cmd := `[Cli|
  verify VIA runVerify; ["0.1.0"]
  "Analyze a Lean 4 project: extract atoms, compute specs, detect sorries, and produce unified output"

  FLAGS:
    o, output : String; "Output file path (default: .verilib/probes/lean_<pkg>_<ver>.json)"
    m, module : String; "Filter to specific module prefix"
    "skip-verify"; "Skip the sorry detection step"
    "skip-build"; "Skip the lake build step (assumes .olean files already exist)"
    "from-file" : String; "Use existing build output for sorry detection instead of running lake"

  ARGS:
    projectPath : String; "Path to the Lean 4 project to analyze"
]

/-- Run the view command -/
def runView (parsed : Parsed) : IO UInt32 := do
  let projectPath := parsed.positionalArg! "projectPath" |>.as! String
  let atomsPath := parsed.flag? "with-atoms" |>.map (·.as! String) |>.map System.FilePath.mk
  let outputPath := parsed.flag? "output" |>.map (·.as! String) |>.map System.FilePath.mk

  let config : ViewConfig := {
    projectPath := projectPath
    atomsPath := atomsPath
    outputPath := outputPath
  }

  runViewInProject config

/-- The view subcommand -/
def viewCmd : Cmd := `[Cli|
  view VIA runView; ["0.1.0"]
  "Generate molecules output from verify results, filtering for the web UI"

  FLAGS:
    a, "with-atoms" : String; "Path to verify output (default: auto-detect from .verilib/probes/)"
    o, output : String; "Output file path (default: .verilib/views/molecules_all.json)"

  ARGS:
    projectPath : String; "Path to the Lean 4 project"
]

/-- Run the root command -/
def runRoot (_parsed : Parsed) : IO UInt32 := do
  IO.println "Use 'probe-lean <command> <PROJECT_PATH>' to analyze a project"
  IO.println "Run 'probe-lean --help' for more information"
  return 0

/-- Main command -/
def probeleanCmd : Cmd := `[Cli|
  "probe-lean" VIA runRoot; ["0.1.0"]
  "A tool for analyzing Lean 4 projects"

  SUBCOMMANDS:
    verifyCmd;
    viewCmd
]

/-- Entry point -/
def main (args : List String) : IO UInt32 :=
  probeleanCmd.validate args
