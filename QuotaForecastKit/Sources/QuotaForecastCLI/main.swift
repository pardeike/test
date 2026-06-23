import Foundation
import QuotaForecastKit
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

private struct InputEnvelope: Decodable {
    let observed: [Double]
    let totalCount: Int?
    let softQuota: Double?
}

private struct Options {
    var observed: [Double]?
    var inputPath: String?
    var outputPath: String?
    var totalCount: Int?
    var softQuota: Double?
    var ensembleSize: Int?
    var seed: UInt64?
    var allowOverrun = true
    var pretty = true
}

private enum CLIError: Error, LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(value) = self { return value }; return nil }
}

@main
private struct Command {
    static func main() {
        do {
            let options = try parse(Array(CommandLine.arguments.dropFirst()))
            let input = try resolve(options)
            var configuration = QuotaForecastConfiguration()
            configuration.softQuota = options.softQuota ?? input.softQuota ?? 100
            if let value = options.ensembleSize { configuration.ensembleSize = value }
            if let value = options.seed { configuration.randomSeed = value }
            configuration.allowOverrun = options.allowOverrun
            let forecast = try QuotaForecaster(configuration: configuration).forecast(
                observed: input.observed,
                totalCount: options.totalCount ?? input.totalCount
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = options.pretty
                ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                : [.sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(forecast)
            if let outputPath = options.outputPath {
                try data.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
            } else {
                FileHandle.standardOutput.write(data)
                FileHandle.standardOutput.write(Data("\n".utf8))
            }
        } catch {
            FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
            FileHandle.standardError.write(Data("Run quota-forecast --help for usage.\n".utf8))
            exit(EXIT_FAILURE)
        }
    }

    private static func parse(_ arguments: [String]) throws -> Options {
        var options = Options()
        var index = 0
        func value(after option: String) throws -> String {
            guard index + 1 < arguments.count else { throw CLIError.message("Missing value after \(option).") }
            index += 1
            return arguments[index]
        }
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--help", "-h": printHelp(); exit(EXIT_SUCCESS)
            case "--observed":
                let raw = try value(after: argument)
                options.observed = try raw.split(separator: ",", omittingEmptySubsequences: false).map {
                    guard let parsed = Double($0.trimmingCharacters(in: .whitespaces)) else {
                        throw CLIError.message("Invalid --observed value: \($0)")
                    }
                    return parsed
                }
            case "--input": options.inputPath = try value(after: argument)
            case "--output": options.outputPath = try value(after: argument)
            case "--total-count":
                let raw = try value(after: argument)
                guard let parsed = Int(raw), parsed > 0 else { throw CLIError.message("Invalid --total-count: \(raw)") }
                options.totalCount = parsed
            case "--soft-quota":
                let raw = try value(after: argument)
                guard let parsed = Double(raw), parsed > 0 else { throw CLIError.message("Invalid --soft-quota: \(raw)") }
                options.softQuota = parsed
            case "--ensemble-size":
                let raw = try value(after: argument)
                guard let parsed = Int(raw), parsed > 0 else { throw CLIError.message("Invalid --ensemble-size: \(raw)") }
                options.ensembleSize = parsed
            case "--seed":
                let raw = try value(after: argument)
                guard let parsed = UInt64(raw) else { throw CLIError.message("Invalid --seed: \(raw)") }
                options.seed = parsed
            case "--no-overrun": options.allowOverrun = false
            case "--compact": options.pretty = false
            default: throw CLIError.message("Unknown argument: \(argument)")
            }
            index += 1
        }
        if options.observed != nil, options.inputPath != nil {
            throw CLIError.message("Use either --observed or --input, not both.")
        }
        return options
    }

    private static func resolve(_ options: Options) throws -> (observed: [Double], totalCount: Int, softQuota: Double?) {
        if let observed = options.observed {
            guard let totalCount = options.totalCount else { throw CLIError.message("Missing --total-count.") }
            return (observed, totalCount, nil)
        }
        guard let path = options.inputPath else {
            throw CLIError.message("Provide --observed or --input.")
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let decoder = JSONDecoder()
        if let observed = try? decoder.decode([Double].self, from: data) {
            guard let totalCount = options.totalCount else { throw CLIError.message("Missing --total-count.") }
            return (observed, totalCount, nil)
        }
        let envelope = try decoder.decode(InputEnvelope.self, from: data)
        guard let totalCount = options.totalCount ?? envelope.totalCount else {
            throw CLIError.message("Missing totalCount in arguments and JSON.")
        }
        return (envelope.observed, totalCount, envelope.softQuota)
    }

    private static func printHelp() {
        print("""
        quota-forecast — dual scenario forecast for cumulative bursty quota usage

        quota-forecast --observed 0,1,3,7,12,12,15 --total-count 40
        quota-forecast --input observed.json --output forecast.json

          --observed VALUES       Comma-separated cumulative observations
          --input PATH            JSON array or object input
          --total-count COUNT     Number of points in the complete window
          --soft-quota VALUE      Soft quota, default 100
          --ensemble-size COUNT   Simulations per scenario, default 384
          --seed UINT64           Deterministic random seed
          --no-overrun            Cap generated paths at softQuota
          --output PATH           Write JSON instead of stdout
          --compact               Emit compact JSON
        """)
    }
}
