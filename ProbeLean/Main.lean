/-
  CLI entry point for probe-lean.
-/
import Cli
import ProbeLean.Atomize

open Cli
open ProbeLean

/-- Run the atomize command -/
def runAtomize (parsed : Parsed) : IO UInt32 := do
  let projectPath := parsed.positionalArg! "projectPath" |>.as! String
  let outputPath := parsed.flag? "output" |>.map (·.as! String) |>.map System.FilePath.mk
  let moduleFilter := parsed.flag? "module" |>.map (·.as! String)

  let config : AtomizeConfig := {
    projectPath := projectPath
    outputPath := outputPath
    moduleFilter := moduleFilter
  }

  runAtomizeInProject config

/-- The atomize subcommand -/
def atomizeCmd : Cmd := `[Cli|
  atomize VIA runAtomize; ["0.1.0"]
  "Analyze a Lean 4 project and output atoms.json dependency graph"

  FLAGS:
    o, output : String; "Output file path (default: PROJECT_PATH/atoms.json)"
    m, module : String; "Filter to specific module prefix"

  ARGS:
    projectPath : String; "Path to the Lean 4 project to analyze"
]

/-- Run the root command -/
def runRoot (_parsed : Parsed) : IO UInt32 := do
  IO.println "Use 'probe-lean atomize <PROJECT_PATH>' to analyze a project"
  IO.println "Run 'probe-lean --help' for more information"
  return 0

/-- Main command -/
def probeleanCmd : Cmd := `[Cli|
  "probe-lean" VIA runRoot; ["0.1.0"]
  "A tool for analyzing Lean 4 projects"

  SUBCOMMANDS:
    atomizeCmd
]

/-- Entry point -/
def main (args : List String) : IO UInt32 :=
  probeleanCmd.validate args
