# Struct Field Alignment

When optimizing Go programs for performance, struct layout and memory alignment often go unnoticed—yet they have a measurable impact on memory usage and cache efficiency. Go automatically aligns struct fields based on platform-specific rules, inserting padding to satisfy alignment constraints. Understanding and controlling this alignment can reduce memory footprint, improve cache locality, and improve performance in tight loops or high-throughput data pipelines.

## Why Alignment Matters

Modern CPUs are sensitive to memory layout. When data is misaligned or spans multiple cache lines, it incurs additional access cycles and can disrupt performance. In Go, struct fields are aligned according to their type requirements, and the compiler inserts padding bytes to meet these constraints. If fields are arranged without care, unnecessary padding may inflate struct size significantly, affecting memory use and bandwidth.

Consider the following two structs:

```go
{%
    include-markdown "01-common-patterns/src/fields-alignment_test.go"
    start="// types-simple-start"
    end="// types-simple-end"
%}
```

On a 64-bit system, `PoorlyAligned` requires 24 bytes due to the padding between fields, whereas `WellAligned` fits into 16 bytes by ordering fields from largest to smallest alignment requirement.

## Benchmarking Impact

We benchmarked both struct layouts by allocating 10 million instances of each and measuring allocation time and memory usage:

```go
{%
    include-markdown "01-common-patterns/src/fields-alignment_test.go"
    start="// simple-start"
    end="// simple-end"
%}
```

Benchmark Results

| Benchmark               | Iterations  | Time per op (ns) | Bytes per op | Allocs per op |
|------------------------|------------|-------------|-------------|------------|
| PoorlyAligned-14       | 177        | 20,095,621  | 240,001,029 | 1          |
| WellAligned-14         | 186        | 19,265,714  | 160,006,148 | 1          |

The WellAligned version reduced memory usage by 80MB for 10 million structs and also ran slightly faster than the poorly aligned version. This highlights that thoughtful field arrangement improves memory efficiency and can yield modest performance gains in allocation-heavy code paths.

## Avoiding False Sharing in Concurrent Workloads

In addition to memory layout efficiency, struct alignment also plays a crucial role in concurrent systems. When multiple goroutines access different fields of the same struct that reside on the same CPU cache line, they may suffer from false sharing—where changes to one field cause invalidations in the other, even if logically unrelated.

On modern CPUs, a typical cache line is 64 bytes wide. When a struct is accessed in memory, the CPU loads the entire cache line that contains it, not just the specific field. This means that two unrelated fields within the same 64-byte block will both reside in the same line—even if they are used independently by separate goroutines. If one goroutine writes to its field, the cache line becomes invalidated and must be reloaded on the other core, leading to degraded performance due to false sharing.

To illustrate, we compared two structs—one vulnerable to false sharing, and another with padding to separate fields across cache lines:

```go
{%
    include-markdown "01-common-patterns/src/fields-alignment_test.go"
    start="// types-shared-start"
    end="// types-shared-end"
%}
```

Each field is incremented by a separate goroutine 1 million times:


```go
{%
    include-markdown "01-common-patterns/src/fields-alignment_test.go"
    start="// shared-start"
    end="// shared-end"
%}
```

1. `FalseSharing` and `NoFalseSharing` benchmarks are identical, except we will use `SharedCounterGood` for the `NoFalseSharing` benchmark.

Benchmark Results:

| Benchmark               | Time per op (ns) | Bytes per op | Allocs per op |
|------------------------|-----------|------|-----------|
| FalseSharing           |   996,234 | 55   | 2         |
| NoFalseSharing         |   958,180 | 58   | 2         |


Placing padding between the two fields prevented false sharing, resulting in a measurable performance improvement. The version with padding completed ~3.8% faster (the value could vary between re-runs from 3% to 6%), which can make a difference in tight concurrent loops or high-frequency counters. It also shows how false sharing may unpredictably affect memory use due to invalidation overhead.

??? example "Show the complete benchmark file"
    ```go
    {% include "01-common-patterns/src/fields-alignment_test.go" %}
    ```

## When To Align Structs

:material-checkbox-marked-circle-outline: Always align structs. It's free to implement and often leads to better memory efficiency without changing any logic—only field order needs to be adjusted.

Guidelines for struct alignment:

- Order fields by decreasing size to reduce internal padding. Larger fields first help prevent unnecessary gaps caused by alignment rules.
- Group same-sized fields together to optimize memory layout. This ensures fields can be packed tightly without additional padding.
- Use padding deliberately to separate fields accessed by different goroutines. Preventing false sharing can improve performance in concurrent applications.
- Avoid interleaving small and large fields. Mixing sizes leads to inefficient memory usage due to extra alignment padding between fields.
- Use the [fieldalignment](https://pkg.go.dev/golang.org/x/tools/go/analysis/passes/fieldalignment) linter to verify. This tool helps catch suboptimal layouts automatically during development.