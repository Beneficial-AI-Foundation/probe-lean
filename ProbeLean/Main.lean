/-
  CLI entry point for probe-lean.
  Two commands: extract (combined atomize+specify+sorry detection) and viewify (molecules output).
-/
import Cli
import ProbeLean.Extract
import ProbeLean.View
import ProbeLean.Version

open Cli
open ProbeLean

/-- Recursively set the version on a command and all its subcommands. -/
partial def Cli.Cmd.withVersion (cmd : Cli.Cmd) (v : String) : Cli.Cmd :=
  .init { cmd.meta with version? := some v }
    cmd.run
    (cmd.subCmds.map (·.withVersion v))
    cmd.extension?

/-- Strip trailing slashes so `FilePath /` doesn't produce `//` in output paths -/
private def normalizePath (s : String) : String :=
  if s.length > 1 && s.endsWith "/" then (s.dropEnd 1).toString else s

/-- Run the extract command -/
def runExtract (parsed : Parsed) : IO UInt32 := do
  let projectPath := normalizePath (parsed.positionalArg! "projectPath" |>.as! String)
  let outputPath := parsed.flag? "output" |>.map (·.as! String) |>.map System.FilePath.mk
  let moduleFilter := parsed.flag? "module" |>.map (·.as! String)
  let skipVerify := parsed.hasFlag "skip-verify"
  let fromFile := parsed.flag? "from-file" |>.map (·.as! String) |>.map System.FilePath.mk
  let libraries := parsed.flag? "library" |>.map fun f =>
    (f.as! String).splitOn "," |>.map (fun s => s.trimAscii.toString) |>.toArray
  let skipEnrich := parsed.hasFlag "skip-enrich"
  let classOverride := (parsed.flag? "class" |>.map (·.as! String)).bind fun s =>
    let t := s.trimAscii.toString
    if t.isEmpty then none else some t

  let config : ExtractConfig := {
    projectPath := projectPath
    outputPath := outputPath
    moduleFilter := moduleFilter
    skipVerify := skipVerify
    fromFile := fromFile
    libraries := libraries
    skipEnrich := skipEnrich
    classOverride := classOverride
  }

  runExtractInProject config

/-- The extract subcommand -/
def extractCmd : Cmd := `[Cli|
  extract VIA runExtract; ["0.0.0"]
  "Analyze a Lean 4 project: extract atoms, compute specs, detect sorries, and produce unified output"

  FLAGS:
    o, output : String; "Output file path (default: .verilib/probes/lean_<pkg>_<ver>.json)"
    m, module : String; "Filter to specific module prefix"
    "skip-verify"; "Skip the sorry detection step"
    "from-file" : String; "Use existing build output for sorry detection instead of running lake"
    l, library : String; "Comma-separated list of library names to build (default: auto-detect from lakefile.toml)"
    "skip-enrich"; "Skip transitive verification enrichment"
    "class" : String; "Override the detected project class (e.g. security-protocol)"

  ARGS:
    projectPath : String; "Path to the Lean 4 project to analyze"
]

/-- Run the viewify command -/
def runView (parsed : Parsed) : IO UInt32 := do
  let projectPath := normalizePath (parsed.positionalArg! "projectPath" |>.as! String)
  let atomsPath := parsed.flag? "with-atoms" |>.map (·.as! String) |>.map System.FilePath.mk
  let outputPath := parsed.flag? "output" |>.map (·.as! String) |>.map System.FilePath.mk

  let config : ViewConfig := {
    projectPath := projectPath
    atomsPath := atomsPath
    outputPath := outputPath
  }

  runViewInProject config

/-- The viewify subcommand -/
def viewCmd : Cmd := `[Cli|
  viewify VIA runView; ["0.0.0"]
  "Generate molecules output from extract results, filtering for the web UI"

  FLAGS:
    a, "with-atoms" : String; "Path to extract output (default: auto-detect from .verilib/probes/)"
    o, output : String; "Output file path (default: .verilib/views/molecules_all.json)"

  ARGS:
    projectPath : String; "Path to the Lean 4 project"
]

/-- Run the root command -/
def runRoot (_parsed : Parsed) : IO UInt32 := do
  IO.println "Use 'probe-lean <command> <PROJECT_PATH>' to analyze a project"
  IO.println "Run 'probe-lean --help' for more information"
  return 0

/-- Main command (version from ProbeLean.version, sourced from lakefile.toml) -/
def probeleanCmd : Cmd :=
  (`[Cli|
    "probe-lean" VIA runRoot; ["0.0.0"]
    "A tool for analyzing Lean 4 projects"

    SUBCOMMANDS:
      extractCmd;
      viewCmd
  ]).withVersion ProbeLean.version

/-- Entry point -/
def main (args : List String) : IO UInt32 :=
  probeleanCmd.validate args
