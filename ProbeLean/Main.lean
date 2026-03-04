/-
  CLI entry point for probe-lean.
-/
import Cli
import ProbeLean.Atomize
import ProbeLean.Specify
import ProbeLean.Verify
import ProbeLean.Stubify
import ProbeLean.Pipeline

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

/-- Run the specify command -/
def runSpecify (parsed : Parsed) : IO UInt32 := do
  let projectPath := parsed.positionalArg! "projectPath" |>.as! String
  let atomsPath := parsed.flag? "with-atoms" |>.map (·.as! String) |>.map System.FilePath.mk
  let outputPath := parsed.flag? "output" |>.map (·.as! String) |>.map System.FilePath.mk

  let config : SpecifyConfig := {
    projectPath := projectPath
    atomsPath := atomsPath
    outputPath := outputPath
  }

  runSpecifyInProject config

/-- The specify subcommand -/
def specifyCmd : Cmd := `[Cli|
  specify VIA runSpecify; ["0.1.0"]
  "Extract specification status from atoms.json"

  FLAGS:
    a, "with-atoms" : String; "Path to atoms.json (default: PROJECT_PATH/.verilib/atoms.json)"
    o, output : String; "Output file path (default: PROJECT_PATH/.verilib/specs.json)"

  ARGS:
    projectPath : String; "Path to the Lean 4 project"
]

/-- Run the verify command -/
def runVerify (parsed : Parsed) : IO UInt32 := do
  let projectPath := parsed.positionalArg! "projectPath" |>.as! String
  let atomsPath := parsed.flag? "with-atoms" |>.map (·.as! String) |>.map System.FilePath.mk
  let outputPath := parsed.flag? "output" |>.map (·.as! String) |>.map System.FilePath.mk
  let noCache := parsed.hasFlag "no-cache"
  let fromFile := parsed.flag? "from-file" |>.map (·.as! String) |>.map System.FilePath.mk

  let config : VerifyConfig := {
    projectPath := projectPath
    atomsPath := atomsPath
    outputPath := outputPath
    noCache := noCache
    fromFile := fromFile
  }

  runVerifyInProject config

/-- The verify subcommand -/
def verifyCmd : Cmd := `[Cli|
  verify VIA runVerify; ["0.1.0"]
  "Check proof completeness by detecting sorry"

  FLAGS:
    a, "with-atoms" : String; "Path to atoms.json (default: PROJECT_PATH/.verilib/atoms.json)"
    o, output : String; "Output file path (default: PROJECT_PATH/.verilib/proofs.json)"
    "no-cache"; "Don't cache verification output"
    "from-file" : String; "Analyze existing build output instead of running lake"

  ARGS:
    projectPath : String; "Path to the Lean 4 project"
]

/-- Run the stubify command -/
def runStubify (parsed : Parsed) : IO UInt32 := do
  let projectPath := parsed.positionalArg! "projectPath" |>.as! String
  let functionsPath := parsed.flag? "functions" |>.map (·.as! String) |>.map System.FilePath.mk
  let outputPath := parsed.flag? "output" |>.map (·.as! String) |>.map System.FilePath.mk

  let config : StubifyConfig := {
    projectPath := projectPath
    functionsPath := functionsPath
    outputPath := outputPath
  }

  runStubifyInProject config

/-- The stubify subcommand -/
def stubifyCmd : Cmd := `[Cli|
  stubify VIA runStubify; ["0.1.0"]
  "Generate stubs.json from functions.json"

  FLAGS:
    f, functions : String; "Path to functions.json (default: PROJECT_PATH/functions.json)"
    o, output : String; "Output file path (default: PROJECT_PATH/.verilib/stubs.json)"

  ARGS:
    projectPath : String; "Path to the Lean 4 project"
]

/-- Run the pipeline command -/
def runPipeline (parsed : Parsed) : IO UInt32 := do
  let projectPath := parsed.positionalArg! "projectPath" |>.as! String
  let outputPath := parsed.flag? "output" |>.map (·.as! String) |>.map System.FilePath.mk
  let moduleFilter := parsed.flag? "module" |>.map (·.as! String)
  let skipVerify := parsed.hasFlag "skip-verify"
  let fromFile := parsed.flag? "from-file" |>.map (·.as! String) |>.map System.FilePath.mk

  let config : PipelineConfig := {
    projectPath := projectPath
    outputPath := outputPath
    moduleFilter := moduleFilter
    skipVerify := skipVerify
    fromFile := fromFile
  }

  runPipelineInProject config

/-- The pipeline subcommand -/
def pipelineCmd : Cmd := `[Cli|
  pipeline VIA runPipeline; ["0.1.0"]
  "Run atomize + specify + verify and produce an enriched atom dict with verification status"

  FLAGS:
    o, output : String; "Output file path (default: PROJECT_PATH/.verilib/graph.json)"
    m, module : String; "Filter to specific module prefix"
    "skip-verify"; "Skip the verification step"
    "from-file" : String; "Use existing build output for verification instead of running lake"

  ARGS:
    projectPath : String; "Path to the Lean 4 project to analyze"
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
    atomizeCmd;
    specifyCmd;
    verifyCmd;
    stubifyCmd;
    pipelineCmd
]

/-- Entry point -/
def main (args : List String) : IO UInt32 :=
  probeleanCmd.validate args
