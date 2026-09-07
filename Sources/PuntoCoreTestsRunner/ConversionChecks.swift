import Foundation
import PuntoCore

/// Exercise the production engine through verified, unknown, failed and superseded writes.
func runConversionChecks() {
    print("\n--- Conversion transactions and receipt reconciliation ---")
    let settings = PuntoSettings(switchingMode: .sequential)
    func prepare(_ engine: PuntoEngine, _ text: String, target: String = "field-A", current: PuntoLanguage? = nil) -> PreparedLayoutConversion {
        guard let value = engine.prepareLayoutConversion(text, settings: settings, currentLanguage: current, targetIdentity: target) else {
            fatalError("Unexpected stale-receipt refusal for conversion test")
        }
        return value
    }

    let cycle = PuntoEngine()
    var text = "csh"
    for (expectedText, expectedLanguage) in [("сыр", PuntoLanguage.russian), ("сір", .ukrainian), ("csh", .english)] {
        let step = prepare(cycle, text)
        assertEqual(step.result.replacementText, expectedText, "Verified cycle replacement")
        assertEqual(step.result.targetLanguage, expectedLanguage, "Verified cycle language")
        assertEqual(cycle.commitPendingConversion(step.token), true, "Commit exact operation")
        assertEqual(cycle.commitPendingConversion(step.token), false, "Token cannot commit twice")
        text = step.result.replacementText
    }

    let scoped = PuntoEngine()
    let first = prepare(scoped, "ghbdtn")
    assertEqual(scoped.commitPendingConversion(first.token), true, "Seed target-A context")
    let other = prepare(scoped, "привет", target: "field-B", current: .ukrainian)
    assertEqual(other.result.sourceLanguage, .ukrainian, "Same text in another field uses current language")
    assertEqual(scoped.discardPendingConversion(other.token), true, "Discard target-B step")

    let stale = PuntoEngine()
    let old = prepare(stale, "csh")
    stale.resetContext()
    assertEqual(stale.commitPendingConversion(old.token), false, "Reset invalidates in-flight operation")
    let newer = prepare(stale, "ghbdtn", target: "field-B")
    assertEqual(stale.discardPendingConversion(old.token), false, "Old failure cannot discard newer work")
    assertEqual(stale.recordUnknownConversion(old.token), false, "Old unknown cannot overwrite newer work")
    assertEqual(stale.commitPendingConversion(newer.token), true, "New operation survives stale callbacks")
    let superseded = prepare(stale, "привет", target: "field-B")
    let newest = prepare(stale, "csh", target: "field-C")
    assertEqual(stale.commitPendingConversion(superseded.token), false, "Preparation supersedes old token")
    assertEqual(stale.discardPendingConversion(superseded.token), false, "Superseded failure is isolated")
    assertEqual(stale.commitPendingConversion(newest.token), true, "Latest preparation commits")
    let foreign = PuntoEngine()
    let foreignPending = prepare(foreign, "csh")
    assertEqual(foreign.commitPendingConversion(newest.token), false, "Tokens are scoped to an engine")
    assertEqual(foreign.commitPendingConversion(foreignPending.token), true, "Foreign token did not consume pending state")

    let unknown = PuntoEngine()
    let unverified = prepare(unknown, "ghbdtn")
    assertEqual(unknown.recordUnknownConversion(unverified.token), true, "Record uncertain delivery")
    assertEqual(unknown.commitPendingConversion(unverified.token), false, "Unknown does not commit")
    assertEqual(unknown.nextLayoutLanguageHint(settings: settings), .russian, "Unknown clears committed cycle")
    for _ in 0..<3 {
        assertEqual(unknown.prepareLayoutConversion("ghbdtn", settings: settings, targetIdentity: "field-A") == nil, true, "Stale AX original never replays unknown write")
    }
    let reconciled = prepare(unknown, "привет", current: .ukrainian)
    assertEqual(reconciled.result.sourceLanguage, .russian, "Fresh expected text restores receipt language")
    assertEqual(reconciled.result.replacementText, "ghbdtn", "Reconciled cycle skips identical RU-UA step")
    assertEqual(unknown.commitPendingConversion(reconciled.token), true, "Reconciled next write commits")

    for resolution in ["other-target", "external-text", "reset"] {
        let engine = PuntoEngine()
        let step = prepare(engine, "ghbdtn")
        assertEqual(engine.recordUnknownConversion(step.token), true, "Create receipt for \(resolution)")
        if resolution == "reset" { engine.resetContext() }
        let input = resolution == "external-text" ? "other" : "ghbdtn"
        let target = resolution == "other-target" ? "field-B" : "field-A"
        assertEqual(engine.prepareLayoutConversion(input, settings: settings, targetIdentity: target) != nil, true, "Receipt clears after \(resolution)")
    }

    let failed = PuntoEngine()
    let seed = prepare(failed, "ghbdtn")
    assertEqual(failed.commitPendingConversion(seed.token), true, "Seed committed context before failure")
    let failure = prepare(failed, "привет")
    assertEqual(failed.discardPendingConversion(failure.token), true, "Failed write discarded")
    let retry = prepare(failed, "привет", current: .ukrainian)
    assertEqual(retry.result.sourceLanguage, .ukrainian, "Failure cannot retain stale committed language")
    _ = failed.convertCase("test", mode: .title)
    assertEqual(failed.commitPendingConversion(retry.token), false, "Case command invalidates pending layout")
    let beforeTransliteration = prepare(failed, "csh")
    _ = failed.transliterate("test", targetLanguage: .russian)
    assertEqual(failed.commitPendingConversion(beforeTransliteration.token), false, "Transliteration invalidates pending layout")

    let fixed = PuntoEngine()
    let fixedSettings = PuntoSettings(switchingMode: .fixedTarget, fixedTargetLanguage: .ukrainian)
    let fixedStep = fixed.prepareLayoutConversion("csh", settings: fixedSettings, targetIdentity: "field-A")!
    assertEqual(fixedStep.result.replacementText, "сір", "Fixed-target preparation transforms")
    assertEqual(fixed.commitPendingConversion(fixedStep.token), true, "Fixed-target receipt commits without sequential context")
}
