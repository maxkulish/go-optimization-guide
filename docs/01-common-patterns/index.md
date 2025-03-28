# Common Go Patterns for Performance

Optimizing Go applications requires understanding common patterns that help reduce latency, improve memory efficiency, and enhance concurrency. This guide organizes 15 key techniques into four practical categories.

---

## Memory Management & Efficiency

These strategies help reduce memory churn, avoid excessive allocations, and improve cache behavior.

- [Object Pooling](./object-pooling.md)  
  Reuse objects to reduce GC pressure and allocation overhead.

- [Memory Preallocation](./mem-prealloc.md)  
  Allocate slices and maps with capacity upfront to avoid costly resizes.

- [Struct Field Alignment](./fields-alignment.md)  
  Optimize memory layout to minimize padding and improve locality.

- [Avoiding Interface Boxing](./interface-boxing.md)  
  Prevent hidden allocations by avoiding unnecessary interface conversions.

- [Zero-Copy Techniques](./zero-copy.md)  
  Minimize data copying with slicing and buffer tricks.

- [Memory Efficiency and Go’s Garbage Collector](./gc.md)  
  Reduce GC overhead by minimizing heap usage and reusing memory.

- [Stack Allocations and Escape Analysis](./stack-alloc.md)  
  Use escape analysis to help values stay on the stack where possible.

---

## Concurrency and Synchronization

Manage goroutines, shared resources, and coordination efficiently.

- [Goroutine Worker Pools](./worker-pool.md)  
  Control concurrency with a fixed-size pool to limit resource usage.

- [Atomic Operations and Synchronization Primitives](./atomic-ops.md)  
  Use atomic operations or lightweight locks to manage shared state.

- [Lazy Initialization (`sync.Once`)](./lazy-init.md)  
  Delay expensive setup logic until it's actually needed.

- [Immutable Data Sharing](./immutable-data.md)  
  Share data safely between goroutines without locks by making it immutable.

- [Efficient Context Management](./context.md)  
  Use `context` to propagate timeouts and cancel signals across goroutines.

---

## I/O Optimization and Throughput

Reduce system call overhead and increase data throughput for I/O-heavy workloads.

- [Efficient Buffering](./buffered-io.md)  
  Use buffered readers/writers to minimize I/O calls.

- [Batching Operations](./batching-ops.md)  
  Combine multiple small operations to reduce round trips and improve throughput.

---

## Compiler-Level Optimization and Tuning

Tap into Go’s compiler and linker to further optimize your application.

- [Leveraging Compiler Optimization Flags](./comp-flags.md)  
  Use build flags like `-gcflags` and `-ldflags` for performance tuning.

- [Stack Allocations and Escape Analysis](./stack-alloc.md)  
  Analyze which values escape to the heap to help the compiler optimize memory placement.
