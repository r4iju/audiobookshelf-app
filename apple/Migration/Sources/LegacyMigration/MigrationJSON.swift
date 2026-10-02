import Foundation

/// JSON coding for every document the migration writes or reads. Legacy Realm doubles can hold NaN
/// or infinity, which plain JSON cannot represent; they are carried as strings instead of failing
/// the whole migration.
enum MigrationJSON {
    private static let nonFinite = (positiveInfinity: "+Infinity", negativeInfinity: "-Infinity", nan: "NaN")

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: nonFinite.positiveInfinity, negativeInfinity: nonFinite.negativeInfinity, nan: nonFinite.nan)
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: nonFinite.positiveInfinity, negativeInfinity: nonFinite.negativeInfinity, nan: nonFinite.nan)
        return decoder
    }
}
