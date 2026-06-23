# QuotaForecastKit

Dependency-free Swift package for completing a partial cumulative quota-usage series with two coherent, step-like scenarios.

- **Optimistic:** prefers lower-intensity historical patterns and applies quota-pressure feedback when projected consumption is too high.
- **Pessimistic:** prefers high-intensity historical patterns and increases the persistence of burst regimes.

Generated values may exceed `100` by default.

## Model

The forecaster does not fit a curve to the cumulative graph. It converts the cumulative input to nonnegative increments, then combines:

1. **TSB intermittent-demand state**: separately estimates activity probability and positive increment size.
2. **Idle / normal / burst regimes**: learned from rolling activity and an empirical transition matrix.
3. **Context-aware block replay**: overlapping historical increment blocks are weighted by recent-context similarity, regime transition probability, recency, adaptive TSB rate, and scenario quantile.
4. **Monte Carlo path selection**: many paths are generated, then one coherent simulation near the scenario endpoint quantile is selected. Pointwise quantiles are deliberately avoided because they smooth away real stair-step geometry.
5. **Quota-aware optimism**: if current pace or the projected endpoint is too high, the optimistic sampler favors quieter blocks and partially scales positive blocks down.

The result preserves plateaus and clustered jumps while remaining monotone after increments are accumulated.

## Library use

```swift
import QuotaForecastKit

let observed: [Double] = [
    0, 1, 3, 7, 12, 12, 12, 13, 13,
    15, 18, 22, 24, 24, 25, 29, 30,
    33, 38, 45, 49,
]

var configuration = QuotaForecastConfiguration()
configuration.softQuota = 100
configuration.allowOverrun = true
configuration.ensembleSize = 384
configuration.randomSeed = 42

let forecast = try QuotaForecaster(configuration: configuration).forecast(
    observed: observed,
    totalCount: 40
)

print(forecast.optimistic.fullSeries)
print(forecast.pessimistic.fullSeries)
print(forecast.optimistic.endpointInterval)
```

`fullSeries` contains the observed prefix plus the generated tail. `futureValues` contains only generated values. `quotaExhaustionIndex` is the first zero-based index at which `softQuota` is reached.

## CLI

```bash
swift build
swift run quota-forecast \
  --observed 0,1,3,7,12,12,12,13,13,15,18,22,24,24,25,29,30,33,38,45,49 \
  --total-count 40
```

Or use JSON:

```bash
swift run quota-forecast --input Examples/observed.json --output forecast.json
```

The JSON input can be an array, with `--total-count` supplied separately, or an object:

```json
{
  "observed": [0, 1, 3, 7, 12, 12, 12, 13],
  "totalCount": 40,
  "softQuota": 100
}
```

CLI options:

```text
--observed VALUES       Comma-separated cumulative observations
--input PATH            JSON array or object input
--total-count COUNT     Number of points in the complete window
--soft-quota VALUE      Soft quota, default 100
--ensemble-size COUNT   Simulations per scenario, default 384
--seed UINT64           Deterministic random seed
--no-overrun            Cap generated paths at softQuota
--output PATH           Write JSON instead of stdout
--compact               Emit compact JSON
```

## Useful tuning

```swift
var configuration = QuotaForecastConfiguration()
configuration.alpha = 0.25
configuration.beta = 0.20
configuration.minBlockLength = 3
configuration.maxBlockLength = 8
configuration.contextLength = 6
configuration.optimisticPatternQuantile = 0.32
configuration.pessimisticPatternQuantile = 0.84
configuration.optimisticConservationStrength = 0.72
configuration.pessimisticMagnitudeMultiplier = 1.10
configuration.quantizationStep = nil // e.g. 0.1 or 1.0 when appropriate
```

Equal inputs, configuration, and seed produce equal output. Runtime scales approximately linearly with `ensembleSize`.

## Input cadence and limits

Observations must be equally spaced. For a seven-day window sampled every 30 minutes, a complete endpoint-inclusive series has `7 * 24 * 2 + 1 = 337` points.

A single partial window contains limited evidence for rare behavior. This is scenario forecasting, not a calibrated guarantee. Calendar effects such as weekdays and time of day require timestamped history and are not inferred from cumulative values alone.
