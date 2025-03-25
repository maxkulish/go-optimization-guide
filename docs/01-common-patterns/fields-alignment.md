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

| Benchmark              | Iterations | ns/op       | B/op        | allocs/op |
|------------------------|------------|-------------|-------------|------------|
| PoorlyAligned-14       | 177        | 20,095,621  | 240,001,029 | 1          |
| WellAligned-14         | 186        | 19,265,714  | 160,006,148 | 1          |

The WellAligned version reduced memory usage by 80MB for 10 million structs and also ran slightly faster than the poorly aligned version. This highlights that thoughtful field arrangement improves memory efficiency and can yield modest performance gains in allocation-heavy code paths.

## Avoiding False Sharing in Concurrent Workloads

In addition to memory layout efficiency, struct alignment also plays a crucial role in concurrent systems. When multiple goroutines access different fields of the same struct that reside on the same CPU cache line, they may suffer from false sharing—where changes to one field cause invalidations in the other, even if logically unrelated.

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

Benchmark Results:

| Benchmark              | ns/op     | B/op | allocs/op |
|------------------------|-----------|------|-----------|
| FalseSharing           |   996,234 | 55   | 2         |
| NoFalseSharing         |   958,180 | 58   | 2         |


Placing padding between the two fields prevented false sharing, resulting in a measurable performance improvement. The version with padding completed ~3.8% faster (the value could vary between runs from 3% to 6%), which can make a difference in tight concurrent loops or high-frequency counters. It also shows how false sharing may unpredictably affect memory use due to invalidation overhead.

??? example "Show the complete benchmark file"
    ```go
    {% include "01-common-patterns/src/fields-alignment_test.go" %}
    ```


## When To Alignment Structs

✅ **ALWAYS** dlignment structs! It's free to implement. No changes except rearrangement are needed!

Guidelines for **struct alignment**:

- Order fields by decreasing size to reduce internal padding.
- Group same-sized fields together to optimize memory layout.
- Use padding deliberately to separate fields accessed by different goroutines.
- Avoid interleaving small and large fields.
- Use [fieldalignment](https://pkg.go.dev/golang.org/x/tools/go/analysis/passes/fieldalignment) linter to verify.
