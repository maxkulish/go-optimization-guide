# Atomic Operations and Synchronization Primitives

In high-concurrency systems, performance isn't just about what you do—it's about what you avoid. Lock contention, cache line bouncing and memory fences quietly shape throughput long before you hit your scaling ceiling. Atomic operations are among the leanest tools Go offers to sidestep these pitfalls.

While Go provides the full suite of synchronization primitives, there's a class of problems where locks feel like overkill. Atomics offers clarity and speed for low-level coordination—counters, flags, and simple state machines, especially under pressure.

## Understanding Atomic Operations

Atomic operations allow safe concurrent access to shared data without explicit locking mechanisms like mutexes. The `sync/atomic` package provides low-level atomic memory primitives ideal for counters, flags, or simple state transitions.

The key benefit of atomic operations is performance under contention. Locking introduces coordination overhead—when many goroutines contend for a mutex, performance can degrade due to context switching and lock queue management. Atomics avoids this by operating directly at the hardware level using CPU instructions like `CAS` (compare-and-swap). This makes them particularly useful for:

- High-throughput counters and flags
- Lock-free queues and freelists
- Low-latency paths where locks are too expensive

### Memory Model and Comparison to C++

Understanding memory models is crucial when reasoning about concurrency. In C++, developers have fine-grained control over atomic operations via memory orderings, which allows them to trade-off between performance and consistency. By default, Go's atomic operations enforce sequential consistency, which means they behave like `std::memory_order_seq_cst` in C++. This is the strongest and safest memory ordering:

- All threads observe atomic operations in the same order.
- Full memory barrier are applied before and after each operation.
- Reads and writes are not reordered across atomic operations.

| C++ Memory Order       | Go Equivalent      | Notes                       |
| ---------------------- | ------------------ | --------------------------- |
| `memory_order_seq_cst` | All `atomic.*` ops | Full sequential consistency |
| `memory_order_acquire` | Not exposed        | Not available in Go         |
| `memory_order_release` | Not exposed        | Not available in Go         |
| `memory_order_relaxed` | Not exposed        | Not available in Go         |

Go does not expose weaker memory models like `relaxed`, `acquire`, or `release`. This is an intentional simplification to promote safety and reduce the risk of subtle data races. All atomic operations in Go imply synchronization across goroutines, ensuring correct behavior without manual memory fencing.

This means you don’t have to reason about instruction reordering or memory visibility at a low level—but it also means you can’t fine-tune for performance in the way C++ or Rust developers might use relaxed atomics.

Low-level access to relaxed memory ordering in Go exists internally (e.g., in the runtime or through `go:linkname`), but it’s not safe or supported for use in application-level code.

### Common Atomic Operations

- `atomic.AddInt64`, `atomic.AddUint32`, etc.: Adds values atomically.
- `atomic.LoadInt64`, `atomic.LoadPointer`: Reads values atomically.
- `atomic.StoreInt64`, `atomic.StorePointer`: Writes values atomically.
- `atomic.CompareAndSwapInt64`: Conditionally updates a value atomically.

### When to Use Atomic Operations in Real Life

#### High-throughput metrics and Counters

Tracking request counts, dropped packets, or other lightweight stats:

```go
var requests int64

func handleRequest() {
	atomic.AddInt64(&requests, 1)
}
```

This code allows multiple goroutines to safely increment a shared counter without using locks. `atomic.AddInt64` ensures each addition is performed atomically, preventing race conditions and keeping performance high under heavy load.

#### Fast, Lock-Free Flags

Simple boolean state shared across threads:

```go
var shutdown int32

func mainLoop() {
	for {
		if atomic.LoadInt32(&shutdown) == 1 {
			break
		}
		// do work
	}
}

func stop() {
	atomic.StoreInt32(&shutdown, 1)
}
```

This pattern allows one goroutine to signal another to stop. `atomic.LoadInt32` reads the flag with synchronization guarantees, and `atomic.StoreInt32` sets the flag in a way visible to all goroutines. It helps implement safe shutdown signals.

#### Once-Only Initialization

Replace `sync.Once` when you need more control:

```go
var initialized int32

func maybeInit() {
	if atomic.CompareAndSwapInt32(&initialized, 0, 1) {
		// initialize resources
	}
}
```

This uses `CompareAndSwapInt32` to ensure only the first goroutine that sees `initialized == 0` will perform the initialization logic. All others skip it. It's efficient and avoids the lock overhead of `sync.Once`, especially when you need conditional or retryable behavior.

#### Lock-Free Queues or Freelist Structures

Building high-performance data structures:

```go
type node struct {
	next *node
	val  any
}

var head atomic.Pointer[node]

func push(n *node) {
	for {
		old := head.Load()
		n.next = old
		if head.CompareAndSwap(old, n) {
			return
		}
	}
}
```

This implements a lock-free stack (LIFO queue). It repeatedly tries to insert a node at the head of the list by atomically replacing the head pointer only if it hasn't changed—a classic `CAS` loop. It's commonly used in object pools and work-stealing queues.

#### Reducing Lock Contention

This approach is common in real-world systems to reduce unnecessary lock contention, such as feature toggles, one-time initialization paths, or conditional caching mechanisms. Atomics serves as a fast-path filter before acquiring a more expensive lock.

Combining atomics with mutexes to gate expensive work:

```go
if atomic.LoadInt32(&someFlag) == 0 {
	return
}
mu.Lock()
defer mu.Unlock()
// do something heavy
```

This pattern is effective when `someFlag` is set by another goroutine, and the current goroutine only uses it as a read-only signal to determine if it should proceed. It avoids unnecessary lock acquisition in high-throughput paths, such as short-circuiting when a feature is disabled or a task has already been completed.

However, if the same goroutine is also responsible forsetting the flag, a simple load followed by a lock is not safe. Another goroutine could interleave between the check and the lock, leading to inconsistent behavior.

To make the operation safe and atomic, use `CompareAndSwap`:

```go
if !atomic.CompareAndSwapInt32(&someFlag, 0, 1) {
	return // work already in progress or completed
}
mu.Lock()
defer mu.Unlock()
// perform one-time expensive initialization
```

This version guarantees that only one goroutine proceeds and others exit early. It ensures both the check and the update to `someFlag` happen atomically.

Here, the atomic read acts as a fast gatekeeper. If the flag is unset, acquiring the mutex is unnecessary. This avoids unnecessary locking in high-frequency code paths, improving responsiveness under load.

## Synchronization Primitives

This section is intentionally kept minimal. Go's synchronization primitives—such as `sync.Mutex`, `sync.RWMutex`, and `sync.Cond`—are already thoroughly documented and widely understood. They are essential tools for managing shared memory and coordinating goroutines, but they are not the focus here.

In the context of this article, we reference them only as a **performance comparison baseline** against atomic operations. When appropriate, these primitives offer clarity and correctness, but they often come at a higher cost in high-contention scenarios, where atomics can provide leaner alternatives.

We’ll use them as contrast points to highlight when and why atomic operations might offer performance advantages.

## Benchmarking Impact

To understand the impact of atomic operations versus mutex locks, we can compare the time taken to increment a shared counter across goroutines using a simple benchmark.


```go
{%
    include-markdown "01-common-patterns/src/atomic-ops_test.go"
    start="// bench-start"
    end="// bench-end"
%}
```

Benchmark results:

| Benchmark                     | Iterations | Time per op | Allocations |
|-------------------------------|------------|-------------|-------------|
| BenchmarkAtomicIncrement-14  | 39,910,514 | 80.40 ns/op | 0 B/op, 0 allocs/op |
| BenchmarkMutexIncrement-14   | 32,629,298 | 110.7 ns/op | 0 B/op, 0 allocs/op |

Atomic operations outperform mutex-based increments in both throughput and latency. The difference becomes more significant under higher contention, where avoiding lock acquisition helps reduce context switching and scheduler overhead.

??? example "Show the complete benchmark file"
    ```go
    {% include "01-common-patterns/src/atomic-ops_test.go" %}
    ```

## When to Use Atomic Operations vs. Mutexes

⚖️ Atomic operations shine in simple, high-frequency scenarios—counters, flags, coordination signals—where the cost of a lock would be disproportionate. They avoid lock queues and reduce context switching. But they come with limitations: no grouping of multiple operations, no rollback, and increased complexity when applied beyond their niche.

⚖️ Mutexes remain the right tool for managing complex shared state, protecting multi-step critical sections, and maintaining invariants. They're easier to reason and generally safer when logic grows beyond a few lines.

Choosing between atomics and locks isn't about ideology but scope. When the job is simple, atomics get out of the way. When the job gets complex, locks keep you safe.
