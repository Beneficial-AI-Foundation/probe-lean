import Lean

/-! The `externally_verified` tag, registered by the dependency and used by both
packages. Rule 2 reads the tag set of the project modules from this extension's
entries. -/

open Lean

initialize externallyVerifiedAttr : TagAttribute ←
  registerTagAttribute `externally_verified "proof discharged outside Lean (fixture)"
