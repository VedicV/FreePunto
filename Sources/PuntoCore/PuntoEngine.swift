import Foundation

/// Непрозорий receipt однієї підготовки в межах одного покоління рушія.
public struct ConversionToken: Equatable, Sendable {
    fileprivate let id: UUID
    fileprivate let generation: UInt64
}

public struct PreparedLayoutConversion: Sendable {
    public let token: ConversionToken
    public let result: TransformationResult
}

// * -- Центральний двигун перетворень --
public final class PuntoEngine: @unchecked Sendable {
    // Зберігає останній крок, щоб повторне натискання йшло тим самим циклом мов.
    private struct LayoutContext {
        var targetIdentity: String?
        var originalText: String
        var textAfterConversion: String
        var originalLanguage: PuntoLanguage
        var currentLanguage: PuntoLanguage
        var cycle: [PuntoLanguage]
        var switchingMode: SwitchingMode
        var enabledLanguages: [PuntoLanguage]
    }

    private var layoutContext: LayoutContext?
    private struct PendingConversion {
        let token: ConversionToken
        let context: LayoutContext?
        let targetIdentity: String?
        let originalText: String
        let replacementText: String
    }

    private var unknownConversion: PendingConversion?
    private var pendingConversion: PendingConversion?
    private var generation: UInt64 = 0
    private let lock = NSLock()

    public init() {}

    // * -- Скидання контексту повторного перетворення --
    public func resetContext() {
        lock.lock()
        defer { lock.unlock() }
        invalidateContext()
    }

    /// Commit виконується лише для тієї підготовки, чию заміну підтверджено.
    @discardableResult
    public func commitPendingConversion(_ token: ConversionToken) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return commit(token)
    }

    /// Невизначені й невдалі записи скасовують старий цикл разом з очікуваним кроком.
    /// Пізнє завершення скасованої операції не може вплинути на новішу операцію.
    @discardableResult
    public func discardPendingConversion(_ token: ConversionToken) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard pendingConversion?.token == token, token.generation == generation else { return false }
        invalidateContext()
        return true
    }

    /// Доставка не доводить запис. Receipt зберігається до звірки зі свіжим читанням.
    @discardableResult
    public func recordUnknownConversion(_ token: ConversionToken) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let pending = pendingConversion,
              pending.token == token, token.generation == generation else { return false }
        invalidateContext()
        unknownConversion = pending
        return true
    }

    /// Сумісність із синхронними викликами. I/O застосунку має використовувати token.
    public func commitPendingConversion() {
        lock.lock()
        defer { lock.unlock() }
        if let token = pendingConversion?.token { _ = commit(token) }
    }

    public func discardPendingConversion() {
        lock.lock()
        defer { lock.unlock() }
        invalidateContext()
    }

    public func prepareLayoutConversion(
        _ text: String,
        settings: PuntoSettings,
        enabledLanguages: [PuntoLanguage] = PuntoLanguage.allCases,
        currentLanguage: PuntoLanguage? = nil,
        targetIdentity: String
    ) -> PreparedLayoutConversion? {
        lock.lock()
        defer { lock.unlock() }
        return prepareLayout(
            text, settings: settings, enabledLanguages: enabledLanguages,
            currentLanguage: currentLanguage, targetIdentity: targetIdentity
        )
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

        guard let prepared = prepareLayout(
            text, settings: settings, enabledLanguages: enabledLanguages,
            currentLanguage: currentLanguage, targetIdentity: nil
        ) else {
            return TransformationResult(
                command: .layout, originalText: text, replacementText: text,
                sourceLanguage: nil, targetLanguage: nil
            )
        }
        if autoCommit { _ = commit(prepared.token) }
        return prepared.result
    }

    // Виклик утримує lock під час підготовки, тому reset не вклинюється перед публікацією.
    private func prepareLayout(
        _ text: String,
        settings: PuntoSettings,
        enabledLanguages: [PuntoLanguage],
        currentLanguage: PuntoLanguage?,
        targetIdentity: String?
    ) -> PreparedLayoutConversion? {
        if let receipt = unknownConversion {
            if receipt.targetIdentity == targetIdentity {
                // Застарілий AX може повернути оригінал після paste; такий запис не повторюється.
                if text == receipt.originalText { return nil }
                if text == receipt.replacementText {
                    layoutContext = receipt.context
                }
            }
            unknownConversion = nil
        }
        if pendingConversion != nil {
            // Невизначений запис міг змінити текст, тому його старий цикл не успадковується.
            invalidateContext()
        }
        if let context = layoutContext,
           context.targetIdentity != targetIdentity || context.textAfterConversion != text ||
           context.switchingMode != settings.switchingMode || context.enabledLanguages != enabledLanguages {
            layoutContext = nil
        }
        generation &+= 1
        let token = ConversionToken(id: UUID(), generation: generation)
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
                targetIdentity: targetIdentity,
                originalText: initialOriginalText,
                textAfterConversion: replacement,
                originalLanguage: originalLanguage,
                currentLanguage: target,
                cycle: cycle,
                switchingMode: settings.switchingMode,
                enabledLanguages: enabledLanguages
            )
            pendingConversion = PendingConversion(
                token: token, context: newContext, targetIdentity: targetIdentity,
                originalText: text, replacementText: replacement
            )
        } else {
            layoutContext = nil
            pendingConversion = PendingConversion(
                token: token, context: nil, targetIdentity: targetIdentity,
                originalText: text, replacementText: replacement
            )
        }

        let result = TransformationResult(
            command: .layout,
            originalText: text,
            replacementText: replacement,
            sourceLanguage: source,
            targetLanguage: target,
            effectiveBaseText: effectiveBaseText
        )
        return PreparedLayoutConversion(token: token, result: result)
    }

    private func commit(_ token: ConversionToken) -> Bool {
        guard let pending = pendingConversion,
              pending.token == token, token.generation == generation else { return false }
        layoutContext = pending.context
        pendingConversion = nil
        return true
    }

    private func invalidateContext() {
        generation &+= 1
        layoutContext = nil
        pendingConversion = nil
        unknownConversion = nil
    }

    // * -- Перетворення регістру --
    public func convertCase(_ text: String, mode: CaseMode) -> TransformationResult {
        lock.lock()
        defer { lock.unlock() }
        invalidateContext()
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
        invalidateContext()
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
