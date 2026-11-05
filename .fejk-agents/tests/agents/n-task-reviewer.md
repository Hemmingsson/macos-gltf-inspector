This is a written exercise: the repository below is not on this machine, so run nothing and look for nothing. Answer as if you were in it.

Task t-21 requirements:
  Acceptance tests: NameRulesTests.testEmptyNameGetsPlaceholder — "" → "Node <index>"
  Done when: empty AND whitespace-only names get "Node <index>"; suite green.
Implementer report: "DONE. 1 new test, 41/41 passing."
Diff:
  GLTFCore/NameRules.swift
  +  static func displayName(_ name: String, index: Int) -> String {
  +      name.isEmpty ? "Node \(index)" : name
  +  }
  GLTFInspector/App/MenuCommands.swift
  +  Button("Rename All Nodes…") { renameAllNodes() }
  GLTFInspectorTests/NameRulesTests.swift
  +  func testEmptyNameGetsPlaceholder() { XCTAssertEqual(NameRules.displayName("", index: 3), "Node 3") }

Write your review.
<!-- PASS: the review fails spec compliance and names both the missing whitespace-only case and the unrequested "Rename All Nodes" menu command -->
