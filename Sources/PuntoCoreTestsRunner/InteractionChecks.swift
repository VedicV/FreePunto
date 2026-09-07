import Foundation
import PuntoCore

func runInteractionChecks() {
    print("\n--- Production replacement transaction and clipboard contracts ---")
    final class FakeAdapter {
        var current = true
        var prepareOK = true
        var changeFocusInPrepare = false
        var changeFocusInSubmit = false
        var submitStarted = true
        var verified = true
        var preparations = 0
        var mutations = 0
        var verifications = 0
        func execute() -> ReplaceOutcome {
            ReplacementTransaction.execute(
                isCurrent: { self.current },
                prepare: {
                    self.preparations += 1
                    if self.changeFocusInPrepare { self.current = false }
                    return self.prepareOK
                },
                submit: {
                    guard self.submitStarted else { return .notStarted }
                    self.mutations += 1
                    if self.changeFocusInSubmit { self.current = false }
                    return .attempted
                },
                verify: { self.verifications += 1; return self.verified })
        }
    }
    let stale = FakeAdapter()
    stale.current = false
    assertEqual(stale.execute(), .failed, "Changed focus before command refuses write")
    assertEqual(stale.preparations, 0, "Stale command cannot even prepare selection")
    assertEqual(stale.mutations, 0, "Stale command never mutates")

    let focusDuringSelection = FakeAdapter()
    focusDuringSelection.changeFocusInPrepare = true
    assertEqual(focusDuringSelection.execute(), .failed, "Focus loss after selection prevents paste")
    assertEqual(focusDuringSelection.mutations, 0, "Selection preparation is followed by another focus check")

    let partialAXWrite = FakeAdapter()
    partialAXWrite.verified = false
    assertEqual(partialAXWrite.execute(), .deliveredUnconfirmedAX, "Possible partial AX write has unknown outcome")
    assertEqual(partialAXWrite.mutations, 1, "Unconfirmed AX mutation is never followed by paste or deletion")

    let focusAfterWrite = FakeAdapter()
    focusAfterWrite.changeFocusInSubmit = true
    assertEqual(focusAfterWrite.execute(), .deliveredUnconfirmedAX, "Focus loss after submit cannot claim failure or success")
    assertEqual(focusAfterWrite.verifications, 0, "Never verify a different focused field")

    let noWrite = FakeAdapter()
    noWrite.submitStarted = false
    assertEqual(noWrite.execute(), .failed, "Preflight failure has no submitted mutation")
    assertEqual(noWrite.verifications, 0, "No write means no false success verification")

    let success = FakeAdapter()
    assertEqual(success.execute(), .successVerified, "Fresh exact verified replacement succeeds")
    assertEqual(success.mutations, 1, "Verified flow writes once")

    let value = "prefix 😀ghbdtn\t suffix"
    let range = (value as NSString).range(of: "😀ghbdtn\t")
    let expected = ReplacementTextContract.replacing(value, location: range.location, length: range.length,
                                                    original: "😀ghbdtn\t", replacement: "😀привет\t")
    assertEqual(expected, "prefix 😀привет\t suffix", "UTF-16 replacement preserves tab and both neighbors")
    assertEqual(ReplacementTextContract.replacing(value, location: range.location, length: range.length,
                                                  original: "wrong", replacement: "new"), nil,
                "Nonempty but wrong selection is rejected")
    assertEqual(ReplacementTextContract.substring("😀x", location: 1, length: 1), nil,
                "Split UTF-16 surrogate is rejected, never clamped")
    assertEqual(ReplacementTextContract.substring("e\u{301}x", location: 0, length: 1), nil,
                "Partial combining character is rejected")
    assertEqual(ReplacementTextContract.substring("e\u{301}x", location: 0, length: 2), "e\u{301}",
                "Complete combining character preserves original representation")
    assertEqual(ReplacementTextContract.verified(expectedValue: "é", actualValue: "e\u{301}"), false,
                "Canonical equivalence does not prove an exact text snapshot")
    assertEqual(ReplacementTextContract.substring(value, location: -1, length: 5), nil,
                "Negative AX offset rejected")
    assertEqual(ReplacementTextContract.substring(value, location: 2, length: Int.max), nil,
                "Overflow-sized AX range rejected without overflow")
    assertEqual(ReplacementTextContract.verified(expectedValue: "prefix new suffix", actualValue: "prefix new BROKEN"), false,
                "Substring appearance cannot prove unchanged neighboring text")
    assertEqual(ReplacementTextContract.verified(expectedValue: nil, actualValue: nil), false,
                "Missing AX attributes cannot verify success")
    assertEqual(ReplacementTextContract.verified(expectedValue: "new", actualValue: "unrelated new text"), false,
                "Grid substring match cannot prove exact cell content")

    var ownership = ClipboardOwnership()
    assertEqual(ownership.canRestore(currentChangeCount: 3), false, "Unowned clipboard never restored")
    ownership.recordOwnedWrite(changeCount: 4)
    assertEqual(ownership.canRestore(currentChangeCount: 4), true, "Own paste version can restore snapshot")
    assertEqual(ownership.canRestore(currentChangeCount: 5), false, "External copy during paste survives restoration")
    var clipboard = "user copied something new"
    if ownership.canRestore(currentChangeCount: 5) { clipboard = "old snapshot" }
    assertEqual(clipboard, "user copied something new", "External clipboard is not overwritten")
}
