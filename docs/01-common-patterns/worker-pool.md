# Goroutine Worker Pools in Go

Go’s lightweight concurrency model makes spawning goroutines nearly free in terms of syntax and initial memory footprint—but that freedom isn’t as cheap as it may seem at first glance. Under high load, unbounded concurrency can quickly lead to excessive memory usage, increased context switching, and unpredictable performance, or even system crashes. A goroutine worker pool introduces controlled parallelism by capping the number of concurrent workers, helping to maintain a balance between resource usage, latency, and throughput.

## Why Worker Pools Matter

While launching a goroutine for every task is idiomatic and often effective, doing so at scale comes with trade-offs. Each goroutine requires stack space and introduces scheduling overhead. Performance can degrade sharply when the number of active goroutines grows, especially in systems handling unbounded input like HTTP requests, jobs from a queue, or tasks from a channel.

A worker pool maintains a fixed number of goroutines that pull tasks from a shared job queue. This creates a backpressure mechanism, ensuring the system never processes more work concurrently than it can handle. Worker pools are particularly valuable when the cost of each task is predictable, and the overall system throughput needs to be stable.

## Basic Worker Pool Implementation

Here’s a minimal implementation of a worker pool:

```go
func worker(id int, jobs <-chan int, results chan<- int) {
    for j := range jobs {
        results <- doWork(j)
    }
}

func doWork(n int) [32]byte {
    data := []byte(fmt.Sprintf("payload-%d", n))
    return sha256.Sum256(data)                  // (1)
}

func main() {
    jobs := make(chan int, 100)
    results := make(chan int, 100)

    for w := 1; w <= 5; w++ {
        go worker(w, jobs, results)
    }

    for j := 1; j <= 10; j++ {
        jobs <- j
    }
    close(jobs)

    for a := 1; a <= 10; a++ {
        <-results
    }
}
```

1. Cryptography is for illustration purposes of CPU-bound code

In this example, five workers pull from the `jobs` channel and push results to the `results` channel. The worker pool limits concurrency to five tasks at a time, regardless of how many tasks are sent.

### Worker Count and CPU Cores

The optimal number of workers in a pool is closely tied to the number of CPU cores, which you can obtain in Go using `runtime.NumCPU()` or `runtime.GOMAXPROCS(0)`. For CPU-bound tasks—where each worker consumes substantial CPU time—you generally want the number of workers to be equal to or slightly less than the number of logical CPU cores. This ensures maximum core utilization without excessive overhead.

If your tasks are I/O-bound (e.g., network calls, disk I/O, database queries), the pool size can be larger than the number of cores. This is because workers will spend much of their time blocked, allowing others to run. In contrast, CPU-heavy workloads benefit from a smaller, tightly bounded pool that avoids contention and context switching.

### Why Too Many Workers Hurts Performance

While adding more workers might seem to increase throughput, this only holds up to a point. Beyond the optimal concurrency level, more workers introduce problems:

- **Scheduler contention**: Go’s runtime has to manage more runnable goroutines than it has CPU cores.
- **Context switching**: Excess goroutines create frequent CPU context switches, wasting cycles.
- **Memory pressure**: Each goroutine consumes stack space; more workers increase memory usage.
- **Cache thrashing**: CPU cache efficiency degrades as goroutines bounce between cores.

This leads to higher latency, more GC activity, and ultimately slower throughput—precisely the opposite of what a well-tuned pool is meant to achieve.

## Benchmarking Impact

Worker pools shine in scenarios where the workload is CPU-bound or where concurrency must be capped to avoid saturating a shared resource (e.g., database connections or file descriptors). Benchmarks comparing unbounded goroutine launches vs. worker pools typically show:

- Lower peak memory usage
- More stable response times under load
- Improved CPU cache locality

??? example "Show the benchmark file"
    ```go
    {% include "01-common-patterns/src/worker-pool_test.go" %}
    ```

Results:

| Benchmark               | Iterations  | Time per op (ns) | Bytes per op | Allocs per op |
|------------------------------|------------|-------------|----------|-----------|
| BenchmarkUnboundedGoroutines-14 | 2,274      | 2,499,213 ns | 639,350  | 39,754    |
| BenchmarkWorkerPool-14         | 3,325      | 1,791,772 ns | 320,707  | 19,762    |

In our benchmark, each task performed a CPU-intensive operation (e.g., cryptographic hashing, math, or serialization). With `workerCount = 10` on an Apple M3 Max machine, the worker pool outperformed the unbounded goroutine model by a significant margin, using fewer resources and completing work faster. Increasing the worker count beyond the number of available cores led to worse performance due to contention.

## When To Use Worker Pools

:material-checkbox-marked-circle-outline: Use a goroutine worker pool when:

- You have a large or unbounded stream of incoming work. A pool helps prevent unbounded goroutine growth, which can lead to memory exhaustion and degraded system performance.
- Processing tasks concurrently can overwhelm system resources. Worker pools provide backpressure and resource control by capping concurrency, helping you avoid CPU thrashing, connection saturation, or I/O overload.
- You want to limit the number of parallel operations for stability. Controlling the number of active workers reduces the risk of spikes in system load, improving predictability and service reliability under pressure.
- Tasks are relatively uniform in cost and benefit from queuing. When task sizes are similar, a fixed pool size ensures efficient throughput and fair task distribution without excessive coordination overhead.

:fontawesome-regular-hand-point-right: Avoid a worker pool when:

- Each task must be processed immediately with minimal latency. Queuing in a worker pool introduces delay. For latency-critical tasks, direct goroutine spawning avoids the scheduling overhead.
- You can rely on Go's scheduler for natural load balancing in low-load scenarios. In light workloads, the overhead of managing a pool may outweigh its benefits. Go’s scheduler can often handle lightweight parallelism efficiently on its own.
- Workload volume is small and bounded. Spinning up goroutines directly keeps code simpler for limited, predictable workloads without risking uncontrolled growth.