import Foundation

// * -- Центральний двигун перетворень --
public final class PuntoEngine: @unchecked Sendable {
    // Зберігає останній крок, щоб повторне натискання йшло тим самим циклом мов.
    private struct LayoutContext {
        var originalText: String
        var textAfterConversion: String
        var originalLanguage: PuntoLanguage
        var currentLanguage: PuntoLanguage
        var cycle: [PuntoLanguage]
        var switchingMode: SwitchingMode
        var enabledLanguages: [PuntoLanguage]
    }

    private var layoutContext: LayoutContext?
    private var pendingLayoutContext: LayoutContext?
    private let lock = NSLock()

    public init() {}

    // * -- Скидання контексту повторного перетворення --
    public func resetContext() {
        lock.lock()
        defer { lock.unlock() }
        layoutContext = nil
        pendingLayoutContext = nil
    }

    // * -- Фіксація відкладеного контексту після успішної заміни --
    public func commitPendingConversion() {
        lock.lock()
        defer { lock.unlock() }
        if let pending = pendingLayoutContext {
            layoutContext = pending
            pendingLayoutContext = nil
        }
    }

    // * -- Скасування відкладеного контексту при невдалій заміні --
    public func discardPendingConversion() {
        lock.lock()
        defer { lock.unlock() }
        pendingLayoutContext = nil
    }

    // * -- Перемикання розкладки за фізичними клавішами --
    public func convertLayout(
        _ text: String,
        settings: PuntoSettings,
        enabledLanguages: [PuntoLanguage] = PuntoLanguage.allCases,
        currentLanguage: PuntoLanguage? = nil,
        autoCommit: Bool = true
    ) -> TransformationResult {
        lock.lock()
        defer { lock.unlock() }

        let fallback = layoutContext?.currentLanguage
            ?? currentLanguage
            ?? (enabledLanguages.contains(.ukrainian) ? .ukrainian : .english)
        let detectedSource = LanguageDetector.detect(text, fallback: fallback)
        let source: PuntoLanguage
        let target: PuntoLanguage
        let cycle: [PuntoLanguage]
        let originalLanguage: PuntoLanguage
        var effectiveBaseText = text
        var isContinuingCycle = false
        var previousOriginalText: String? = nil

        switch settings.switchingMode {
        case .sequential:
            // Продовжувати цикл можна тільки коли реально прочитаний text збігається з textAfterConversion
            // і набір доступних мов не змінився.
            isContinuingCycle = layoutContext != nil &&
                layoutContext?.textAfterConversion == text &&
                layoutContext?.switchingMode == settings.switchingMode &&
                layoutContext?.enabledLanguages == enabledLanguages

            if let context = layoutContext,
               isContinuingCycle,
               let index = context.cycle.firstIndex(of: context.currentLanguage) {
                cycle = context.cycle
                source = context.currentLanguage
                originalLanguage = context.originalLanguage
                previousOriginalText = context.originalText

                let baseText = text

                // Шукаємо наступну мову в циклі, яка реально змінює текст
                var nextIndex = (index + 1) % cycle.count
                var candidateTarget = cycle[nextIndex]
                var candidateReplacement = LayoutTransformer.transform(baseText, from: source, to: candidateTarget)
                while candidateReplacement == baseText && nextIndex != index {
                    nextIndex = (nextIndex + 1) % cycle.count
                    candidateTarget = cycle[nextIndex]
                    candidateReplacement = LayoutTransformer.transform(baseText, from: source, to: candidateTarget)
                }
                target = candidateTarget
                effectiveBaseText = baseText
            } else {
                source = detectedSource
                cycle = Self.cycle(startingWith: source, enabled: enabledLanguages)
                originalLanguage = source

                // Шукаємо першу цільову мову в циклі, яка реально змінює текст
                var nextIndex = cycle.count > 1 ? 1 : 0
                var candidateTarget = cycle[nextIndex]
                var candidateReplacement = LayoutTransformer.transform(text, from: source, to: candidateTarget)
                var step = 1
                while candidateReplacement == text && step < cycle.count {
                    step += 1
                    nextIndex = (nextIndex + 1) % cycle.count
                    candidateTarget = cycle[nextIndex]
                    candidateReplacement = LayoutTransformer.transform(text, from: source, to: candidateTarget)
                }
                target = candidateTarget
            }
        case .fixedTarget:
            source = detectedSource
            cycle = []
            originalLanguage = source
            target = source == .english ? settings.fixedTargetLanguage : .english
        }

        let replacement = LayoutTransformer.transform(effectiveBaseText, from: source, to: target)
        if settings.switchingMode == .sequential {
            let initialOriginalText = isContinuingCycle ? (previousOriginalText ?? text) : text
            let newContext = LayoutContext(
                originalText: initialOriginalText,
                textAfterConversion: replacement,
                originalLanguage: originalLanguage,
                currentLanguage: target,
                cycle: cycle,
                switchingMode: settings.switchingMode,
                enabledLanguages: enabledLanguages
            )
            if autoCommit {
                layoutContext = newContext
                pendingLayoutContext = nil
            } else {
                pendingLayoutContext = newContext
            }
        } else {
            layoutContext = nil
            pendingLayoutContext = nil
        }

        return TransformationResult(
            command: .layout,
            originalText: text,
            replacementText: replacement,
            sourceLanguage: source,
            targetLanguage: target,
            effectiveBaseText: effectiveBaseText
        )
    }

    // * -- Перетворення регістру --
    public func convertCase(_ text: String, mode: CaseMode) -> TransformationResult {
        lock.lock()
        defer { lock.unlock() }
        layoutContext = nil
        pendingLayoutContext = nil
        return TransformationResult(
            command: .letterCase,
            originalText: text,
            replacementText: CaseTransformer.transform(text, mode: mode),
            sourceLanguage: nil,
            targetLanguage: nil
        )
    }

    // * -- Транслітерація окремою командою --
    public func transliterate(_ text: String, targetLanguage: PuntoLanguage) -> TransformationResult {
        lock.lock()
        defer { lock.unlock() }
        layoutContext = nil
        pendingLayoutContext = nil
        return Transliterator.transliterate(text, targetLanguage: targetLanguage)
    }

    // * -- Підказка для статусної іконки --
    public func nextLayoutLanguageHint(
        settings: PuntoSettings,
        enabledLanguages: [PuntoLanguage] = PuntoLanguage.allCases
    ) -> PuntoLanguage {
        lock.lock()
        defer { lock.unlock() }

        guard settings.isEnabled else {
            return layoutContext?.currentLanguage ?? settings.fixedTargetLanguage
        }

        switch settings.switchingMode {
        case .fixedTarget:
            return settings.fixedTargetLanguage
        case .sequential:
            guard let context = layoutContext,
                  context.enabledLanguages == enabledLanguages,
                  let index = context.cycle.firstIndex(of: context.currentLanguage) else {
                let cycle = Self.cycle(startingWith: .english, enabled: enabledLanguages)
                return cycle.count > 1 ? cycle[1] : (enabledLanguages.contains(.russian) ? .russian : .ukrainian)
            }
            return context.cycle[(index + 1) % context.cycle.count]
        }
    }

    // Цикл завжди починається з поточної мови, щоб наступний елемент cycle[1] був правильною наступною мовою.
    // Детермінований порядок кругової заміни: English -> Russian -> Ukrainian -> English
    private static func cycle(startingWith language: PuntoLanguage, enabled: [PuntoLanguage]) -> [PuntoLanguage] {
        let fullCycle: [PuntoLanguage] = [.english, .russian, .ukrainian]

        var filtered = fullCycle.filter { enabled.contains($0) }
        if filtered.isEmpty {
            filtered = fullCycle
        }

        if !filtered.contains(language) {
            return [language] + filtered
        }

        if let idx = filtered.firstIndex(of: language) {
            return Array(filtered[idx...] + filtered[..<idx])
        }
        return filtered
    }
}
