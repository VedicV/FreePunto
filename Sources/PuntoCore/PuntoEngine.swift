import Foundation

// * -- Центральний двигун перетворень --
public final class PuntoEngine: @unchecked Sendable {
    // Зберігає останній крок, щоб повторне натискання йшло тим самим циклом мов.
    private struct LayoutContext {
        var textAfterConversion: String
        var originalLanguage: PuntoLanguage
        var currentLanguage: PuntoLanguage
        var cycle: [PuntoLanguage]
        var switchingMode: SwitchingMode
    }

    private var layoutContext: LayoutContext?

    public init() {}

    // * -- Скидання контексту повторного перетворення --
    public func resetContext() {
        layoutContext = nil
    }

    // * -- Перемикання розкладки за фізичними клавішами --
    public func convertLayout(_ text: String, settings: PuntoSettings) -> TransformationResult {
        let fallback = layoutContext?.currentLanguage ?? .english
        let detectedSource = LanguageDetector.detect(text, fallback: fallback)
        let source: PuntoLanguage
        let target: PuntoLanguage
        let cycle: [PuntoLanguage]
        let originalLanguage: PuntoLanguage

        switch settings.switchingMode {
        case .sequential:
            // Якщо користувач знову натиснув на вже перетворений фрагмент, продовжуємо попередній цикл.
            if let context = layoutContext,
               context.textAfterConversion == text,
               context.switchingMode == settings.switchingMode,
               let index = context.cycle.firstIndex(of: context.currentLanguage) {
                cycle = context.cycle
                source = context.currentLanguage
                target = cycle[(index + 1) % cycle.count]
                originalLanguage = context.originalLanguage
            } else {
                source = detectedSource
                cycle = Self.cycle(startingWith: source)
                target = cycle[1]
                originalLanguage = source
            }
        case .fixedTarget:
            source = detectedSource
            cycle = []
            originalLanguage = source
            target = source == .english ? settings.fixedTargetLanguage : .english
        }

        let replacement = LayoutTransformer.transform(text, from: source, to: target)
        if settings.switchingMode == .sequential {
            layoutContext = LayoutContext(
                textAfterConversion: replacement,
                originalLanguage: originalLanguage,
                currentLanguage: target,
                cycle: cycle,
                switchingMode: settings.switchingMode
            )
        } else {
            layoutContext = nil
        }

        return TransformationResult(
            command: .layout,
            originalText: text,
            replacementText: replacement,
            sourceLanguage: source,
            targetLanguage: target
        )
    }

    // * -- Перетворення регістру --
    public func convertCase(_ text: String, mode: CaseMode) -> TransformationResult {
        layoutContext = nil
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
        layoutContext = nil
        return Transliterator.transliterate(text, targetLanguage: targetLanguage)
    }

    // * -- Підказка для статусної іконки --
    public func nextLayoutLanguageHint(settings: PuntoSettings) -> PuntoLanguage {
        guard settings.isEnabled else {
            return layoutContext?.currentLanguage ?? settings.fixedTargetLanguage
        }

        switch settings.switchingMode {
        case .fixedTarget:
            return settings.fixedTargetLanguage
        case .sequential:
            guard let context = layoutContext,
                  let index = context.cycle.firstIndex(of: context.currentLanguage) else {
                return .russian
            }
            return context.cycle[(index + 1) % context.cycle.count]
        }
    }

    // Цикл залежить від мови початкового фрагмента, щоб повторними натисканнями можна було повернутися назад.
    private static func cycle(startingWith language: PuntoLanguage) -> [PuntoLanguage] {
        switch language {
        case .english:
            return [.english, .russian, .ukrainian]
        case .russian:
            return [.russian, .english, .ukrainian]
        case .ukrainian:
            return [.ukrainian, .english, .russian]
        }
    }
}
