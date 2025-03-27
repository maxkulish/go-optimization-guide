# Batching Operations in Go

Batching is a simple but effective way to boost performance in high-throughput Go applications. By grouping multiple operations into a single call, you can minimize repeated overhead—from network round-trips and disk I/O to database commits and CPU cycles. It’s a practical technique that can make a big difference in both latency and resource usage.

## Why Batching Matters

Systems frequently encounter performance issues not because individual operations are inherently costly, but because they occur in high volume. Each call to external resources—such as APIs, databases, or storage—introduces latency, system calls, and potential context switching. Batching groups these operations to minimize repeated overhead, substantially improving throughput and efficiency.

Consider a logging service writing to disk:

```go
func logLine(line string) {
    f.WriteString(line + "\n")
}
```

When invoked thousands of times per second, the file system is inundated with individual write system calls, significantly degrading performance. A better approach could be aggregates log entries and flushes them in bulk:

```go
var batch []string

func logBatch(line string) {
    batch = append(batch, line)
    if len(batch) >= 100 {
        f.WriteString(strings.Join(batch, "\n") + "\n")
        batch = batch[:0]
    }
}
```

With batching, each write operation handles multiple entries simultaneously, reducing syscall overhead and improving disk I/O efficiency.

!!! warning
    While batching offers substantial performance advantages, it also introduces the risk of data loss. If an application crashes before a batch is flushed, the in-memory data can be lost. Systems dealing with critical or transactional data must incorporate safeguards such as periodic flushes, persistent storage buffers, or recovery mechanisms to mitigate this risk.

## How generic Batcher may looks like

We can implement a generic batcher in very straight forward manner:

```go
type Batcher[T any] struct {
    mu     sync.Mutex
    buffer []T
    size   int
    flush  func([]T)
}

func NewBatcher[T any](size int, flush func([]T)) *Batcher[T] {
    return &Batcher[T]{
        buffer: make([]T, 0, size),
        size:   size,
        flush:  flush,
    }
}

func (b *Batcher[T]) Add(item T) {
    b.mu.Lock()
    defer b.mu.Unlock()
    b.buffer = append(b.buffer, item)
    if len(b.buffer) >= b.size {
        b.flushNow()
    }
}

func (b *Batcher[T]) flushNow() {
    if len(b.buffer) == 0 {
        return
    }
    b.flush(b.buffer)
    b.buffer = b.buffer[:0]
}
```

This batcher works with any data type, making it a flexible solution for aggregating logs, metrics, database writes, or other grouped operations. Internally, the buffer acts as a queue that accumulates items until a flush threshold is reached. The use of `sync.Mutex` ensures that `Add()` and `flushNow()` are safe for concurrent access, which is necessary in most real-world systems where multiple goroutines may write to the batcher.

From a performance standpoint, it's true that a lock-free implementation—using atomic operations or concurrent ring buffers—could reduce contention and improve throughput under heavy load. However, such designs are more complex, harder to maintain, and generally not justified unless you're pushing extremely high concurrency or low-latency boundaries. For most practical workloads, the simplicity and safety of a `sync.Mutex`-based design offers a great balance between performance and maintainability.


## Benchmarking Impact

To validate batching performance, we tested six scenarios across three categories: in-memory processing, file I/O, and CPU-intensive hashing. Each category included both unbatched and batched variants, with all benchmarks running over 10,000 items per operation.

??? example "Show the benchmark file"
    ```go
    {% include "01-common-patterns/src/batching-ops_test.go" %}
    ```

```
BenchmarkUnbatchedProcessing-14              530           2028492 ns/op         1279850 B/op      10000 allocs/op
BenchmarkBatchedProcessing-14                573           2094168 ns/op         2457603 B/op        200 allocs/op
BenchmarkUnbatchedIO-14                       87          12766433 ns/op         1280424 B/op      10007 allocs/op
BenchmarkBatchedIO-14                       1324            993912 ns/op         2458026 B/op        207 allocs/op
BenchmarkUnbatchedCrypto-14                  978           1232242 ns/op         2559840 B/op      30000 allocs/op
BenchmarkBatchedCrypto-14                   1760            675303 ns/op         2470406 B/op        400 allocs/op
```
In-memory string manipulation showed a modest performance delta. While the batched variant reduced memory allocations by 50x, the execution time was only marginally slower due to the cost of joining large strings. This highlights that batching isn’t always faster in raw throughput, but it consistently reduces pressure on the garbage collector.

File I/O benchmarks showed the most dramatic gains. The batched version was over 12 times faster than the unbatched one, with far fewer syscalls and significantly lower execution time. Grouping disk writes amortized the I/O cost, leading to a huge efficiency boost despite temporarily using more memory.

The cryptographic benchmarks demonstrated batching’s value in CPU-bound scenarios. Batched hashing nearly halved the total processing time while reducing allocation count by more than 70x. This reinforces batching as an effective strategy even in CPU-intensive workloads where fewer operations yield better locality and cache behavior.
## When To Use Batching

✅ Use batching when:

- Individual operations are expensive (e.g., I/O, RPC, DB writes). Grouping multiple operations into a single batch reduces the overhead of repeated calls and improves efficiency.
- The system benefits from reducing the frequency of external interactions. Fewer external calls can ease load on downstream systems and reduce contention or rate-limiting issues.
- You have some tolerance for per-item latency in favor of higher throughput. Batching introduces slight delays but can significantly increase overall system throughput.

❌ Avoid batching when:

- Immediate action is required for each individual input. Delaying processing to build a batch may violate time-sensitive requirements.
- Holding data introduces risk (e.g., crash before flush). If data must be processed or persisted immediately to avoid loss, batching can be unsafe.
- Predictable latency is more important than throughput. Batching adds variability in timing, which may not be acceptable in systems with strict latency expectations.