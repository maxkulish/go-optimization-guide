# Memory Efficiency: Mastering Go’s Garbage Collector

Memory management in Go is automated—but it’s not invisible. Every allocation you make contributes to GC workload. The more frequently objects are created and discarded, the more work the runtime has to do reclaiming memory.

This becomes especially relevant in systems that prioritize low latency, predictable resource usage, or high throughput. Tuning your allocation patterns and leveraging newer features like weak references can help reduce pressure on the GC without adding complexity to your code.

---

## How Go's Garbage Collector Works

Go uses a **non-generational, concurrent, tri-color mark-and-sweep** garbage collector. Here's what that means in practice and how it's implemented.

### Non-generational

Many modern GCs, like those in the JVM or .NET CLR, divide memory into *generations* (young and old) under the assumption that most objects die young. These collectors focus on the young generation, which leads to shorter collection cycles.

Go’s GC takes a different approach. It treats all objects equally—no generational segmentation—because it prioritizes simplicity, short pause times, and concurrent scanning. This design avoids the need for promotion logic or complex memory regions. While it does mean that the GC may scan more objects overall, this is mitigated by concurrent execution and fast write barriers.

### Concurrent

Go’s GC runs concurrently with your application, which means it does most of its work without stopping the world. Concurrency is implemented using multiple phases that interleave with normal program execution:

- **STW Start Phase:** The application is briefly paused to initiate GC. The runtime scans stacks, globals, and root objects.
- **Concurrent Mark Phase:** The GC walks the heap graph and marks reachable objects in parallel with your program. This is the most substantial phase and runs concurrently with minimal interference.
- **STW Mark Termination:** A short pause occurs to finalize marking and ensure consistency.
- **Concurrent Sweep Phase:** The GC reclaims memory from unreachable (white) objects and returns it to the heap for reuse, all while your program continues running.

Write barriers ensure correctness while the application mutates objects during concurrent marking. These barriers help track references created or modified mid-scan so the GC doesn’t miss them.

### Tri-color Mark and Sweep

The tri-color algorithm organizes heap objects into three sets:

- **White**: Unreachable objects (candidates for collection)
- **Grey**: Reachable but not fully scanned (discovered but not processed)
- **Black**: Reachable and fully scanned (safe from collection)

The GC begins by marking root objects as grey. It then processes each grey object, scanning its fields:
- Any referenced objects not already marked are added to the grey set.
- Once all references are scanned, the object is turned black.

Objects left white at the end of the mark phase are unreachable and swept during the sweep phase.

A key optimization is **incremental marking**: Go spreads out GC work to avoid long pauses, supported by precise stack scanning and conservative write barriers. The use of concurrent sweeping further reduces latency, allowing memory to be reclaimed without halting execution.

This design gives Go a GC that’s safe, fast, and friendly to server workloads with large heaps and many cores.

## GC Tuning: GOGC

The `GOGC` environment variable controls the GC aggressiveness:

```bash
GOGC=100  # default, triggers GC when heap size grows by 100%
GOGC=off  # disables GC entirely
```

Lowering GOGC (e.g., `GOGC=50`) triggers more frequent collections, reducing peak heap size but increasing CPU usage. Raising it reduces GC frequency but can increase memory usage.

## Practical Strategies for Reducing GC Pressure

### Minimize Allocation Rate

GC cost is proportional to the allocation rate. Avoid unnecessary allocations:

```go
// BAD: creates a new slice every time
func copyData(data []byte) []byte {
    return append([]byte{}, data...)
}

// BETTER: reuse buffers when possible
var bufPool = sync.Pool{
    New: func() interface{} { return make([]byte, 0, 1024) },
}

func copyData(data []byte) []byte {
    buf := bufPool.Get().([]byte)
    buf = buf[:0]              // reset buffer
    buf = append(buf, data...)
    defer bufPool.Put(buf)
    return buf
}
```

See [Object Pooling](./object-pooling.md) for more details.

### Prefer Stack Allocation

Go allocates variables on the stack whenever possible. Avoid escaping variables to the heap:

```go
// BAD: returns pointer to heap-allocated struct
func newUser(name string) *User {
    return &User{Name: name}  // escapes to heap
}

// BETTER: use value types if pointer is unnecessary
func printUser(u User) {
    fmt.Println(u.Name)
}
```

Use `go build -gcflags="-m"` to view escape analysis diagnostics.

### Use sync.Pool for Short-Lived Objects

`sync.Pool` is ideal for temporary, reusable allocations that are expensive to GC.

```go
var bufPool = sync.Pool{
    New: func() interface{} { return new(bytes.Buffer) },
}

func handler(w http.ResponseWriter, r *http.Request) {
    buf := bufPool.Get().(*bytes.Buffer)
    buf.Reset()
    defer bufPool.Put(buf)

    // Use buf...
}
```

See [Object Pooling](./object-pooling.md) for more details.

### Batch Allocations

Group allocations into fewer objects to reduce GC pressure.

```go
// Instead of allocating many small structs, allocate a slice of structs
users := make([]User, 0, 1000)  // single large allocation
```

See [Memory Preallocation](./mem-prealloc.md) for more details.

## Weak References in Go

### Using `runtime.SetFinalizer`

Prior to Go 1.24, Go did not natively support weak references, but it was possible to simulate them using `runtime.SetFinalizer`. This allowed developers to run cleanup logic or remove metadata from side-channel maps when an object was garbage collected.

```go
package main

import (
    "fmt"
    "runtime"
    "time"
)

type Object struct {
    Name string
}

func main() {
    weakMap := make(map[*Object]string)

    obj := &Object{Name: "transient"}
    weakMap[obj] = "metadata"

    runtime.SetFinalizer(obj, func(o *Object) {
        fmt.Println("Finalizer called for:", o.Name)
        delete(weakMap, o)  // clean up metadata manually
    })

    obj = nil  // remove strong reference
    runtime.GC()

    time.Sleep(1 * time.Second)
    fmt.Println("Remaining in weakMap:", len(weakMap))
}
```

### Native Weak Pointers with the `weak` Package (Go 1.24+)

Go 1.24 introduced the `weak` package, which offers a safer and standardized way to create weak references. Weak pointers do not prevent an object from being garbage collected, and can be checked for availability.

```go
package main

import (
    "fmt"
    "runtime"
    "weak"
)

type Data struct {
    Value string
}

func main() {
    data := &Data{Value: "Important"}
    wp := weak.Make(data) // create weak pointer

    fmt.Println("Original:", wp.Value().Value)

    data = nil // remove strong reference
    runtime.GC()

    if v := wp.Value(); v != nil {
        fmt.Println("Still alive:", v.Value)
    } else {
        fmt.Println("Data has been collected")
    }
}
```

This is particularly useful for memory-sensitive structures like caches or canonicalization maps. Always check the result of `Value()` to confirm the object is still valid.

## Observing and Debugging the GC

Use the built-in runtime and `pprof` tools:

```go
import "runtime"

var memStats runtime.MemStats
runtime.ReadMemStats(&memStats)
fmt.Printf("NumGC: %v, HeapAlloc: %v\n", memStats.NumGC, memStats.HeapAlloc)
```

Visualize GC performance using:
```bash
go run main.go
curl http://localhost:6060/debug/pprof/heap
```
