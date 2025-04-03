# Object Pooling

Object pooling is a practical way to cut down on memory allocation costs in performance-critical Go applications. Instead of creating and discarding objects repeatedly, you reuse them from a shared pool—saving both CPU time and pressure on the garbage collector.

Go’s `sync.Pool` makes this pattern easy to implement, especially when you’re working with short-lived objects that are created and discarded often. It’s a simple tool that can help smooth out GC behavior and improve throughput under load.

## How Object Pooling Works

Object pooling allows objects to be reused rather than allocated anew, minimizing the strain on the garbage collector. Instead of requesting new memory from the heap each time, objects are fetched from a pre-allocated pool and returned when no longer needed. This reduces allocation overhead and improves runtime efficiency.

### Using `sync.Pool` for Object Reuse

#### Without Object Pooling (Inefficient Memory Usage)
```go
package main

import (
    "fmt"
)

type Data struct {
    Value int
}

func createData() *Data {
    return &Data{Value: 42}
}

func main() {
    for i := 0; i < 1000000; i++ {
        obj := createData() // Allocating a new object every time
        _ = obj // Simulate usage
    }
    fmt.Println("Done")
}
```

In the above example, every iteration creates a new `Data` instance, leading to unnecessary allocations and increased GC pressure.

#### With Object Pooling (Optimized Memory Usage)
```go
package main

import (
    "fmt"
    "sync"
)

type Data struct {
    Value int
}

var dataPool = sync.Pool{
    New: func() any {
        return &Data{}
    },
}

func main() {
    for i := 0; i < 1000000; i++ {
        obj := dataPool.Get().(*Data) // Retrieve from pool
        obj.Value = 42 // Use the object
        dataPool.Put(obj) // Return object to pool for reuse
    }
    fmt.Println("Done")
}
```

### Pooling Byte Buffers for Efficient I/O

Object pooling is especially effective when working with large byte slices that would otherwise lead to high allocation and garbage collection overhead.

```go
package main

import (
    "bytes"
    "fmt"
    "sync"
)

var bufferPool = sync.Pool{
    New: func() any {
        return new(bytes.Buffer)
    },
}

func main() {
    buf := bufferPool.Get().(*bytes.Buffer)
    buf.Reset()
    buf.WriteString("Hello, pooled world!")
    fmt.Println(buf.String())
    bufferPool.Put(buf) // Return buffer to pool for reuse
}
```

Using `sync.Pool` for byte buffers significantly reduces memory pressure when dealing with high-frequency I/O operations.

## Benchmarking Impact

To prove that object pooling actually reduces allocations and improves speed, we can use Go's built-in memory profiling tools (`pprof`) and compare memory allocations between the non-pooled and pooled versions. Simulating a full-scale application that actively uses memory for benchmarking is challenging, so we need a controlled test to evaluate direct heap allocations versus pooled allocations.

??? example "Show the benchmark file"
    ```go
    {% include "01-common-patterns/src/object-pooling_test.go" %}
    ```

| Benchmark               | Iterations  | Time per op (ns) | Bytes per op | Allocs per op |
|-------------------------|-------------|------------------|---------------|----------------|
| BenchmarkWithoutPooling-14 | 1,692,014   | 705.4            | 8,192         | 1              |
| BenchmarkWithPooling-14    | 160,440,506 | 7.455            | 0             | 0              |

The benchmark results highlight the performance and memory usage differences between direct allocations and object pooling. The `BenchmarkWithoutPooling` function demonstrates higher execution time and memory consumption due to frequent heap allocations, resulting in increased garbage collection cycles. A nonzero allocation count confirms that each iteration incurs a heap allocation, contributing to GC overhead and slower performance.

## When Should You Use `sync.Pool`?

:material-checkbox-marked-circle-outline: Use sync.Pool when:

- You have short-lived, reusable objects (e.g., buffers, scratch memory, request state). Pooling avoids repeated allocations and lets you recycle memory efficiently.
- Allocation overhead or GC churn is measurable and significant. Reusing objects reduces the number of heap allocations, which in turn lowers garbage collection frequency and pause times.
- The object’s lifecycle is local and can be reset between uses. When objects don’t need complex teardown and are safe to reuse after a simple reset, pooling is straightforward and effective.
- You want to reduce pressure on the garbage collector in high-throughput systems. In systems handling thousands of requests per second, pooling helps maintain consistent performance and minimizes GC-related latency spikes.

:fontawesome-regular-hand-point-right: Avoid sync.Pool when:

- Objects are long-lived or shared across multiple goroutines. `sync.Pool` is optimized for short-lived, single-use objects and doesn’t manage shared ownership or coordination.
- The reuse rate is low and pooled objects are not frequently accessed. If objects sit idle in the pool, you gain little benefit and may even waste memory.
- Predictability or lifecycle control is more important than allocation speed. Pooling makes lifecycle tracking harder and may not be worth the tradeoff.
- Memory savings are negligible or code complexity increases significantly. If pooling doesn’t provide clear benefits, it can add unnecessary complexity to otherwise simple code.