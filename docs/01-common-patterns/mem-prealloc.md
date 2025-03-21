# Memory Preallocation

Memory preallocation is a straightforward yet highly effective performance optimization strategy in Go. By allocating the required memory upfront, developers can eliminate hidden overhead related to dynamic resizing—such as memory allocations, data copying, and increased garbage collection frequency. This approach enhances application predictability and performance, particularly beneficial in performance-critical or high-throughput environments.

## Why Preallocation Matters

In Go, slices and maps dynamically expand to accommodate new elements. While convenient, this automatic growth introduces overhead. When a slice or map reaches its capacity, Go must allocate a new memory block and copy existing data into it. Frequent resizing operations significantly degrade performance, especially within tight loops or resource-intensive tasks.

Go employs a specific growth strategy for slices to balance memory efficiency and performance. Initially, slice capacities double with each expansion, ensuring rapid growth. However, once a slice exceeds approximately 1024 elements, the capacity growth rate reduces to about 25%. For example, starting from a capacity of 1, slices grow sequentially to capacities of 2, 4, 8, and so forth. But after surpassing 1024 elements, the next capacity increment would typically be around 1280 rather than doubling to 2048. This controlled growth reduces memory waste but increases allocation frequency if the final slice size is predictable but not explicitly preallocated.

```go
s := make([]int, 0)
for i := 0; i < 10_000; i++ {
    s = append(s, i)
    fmt.Printf("Len: %d, Cap: %d\n", len(s), cap(s))
}
```

Output illustrating typical growth:

```
Len: 1, Cap: 1
Len: 2, Cap: 2
Len: 3, Cap: 4
Len: 5, Cap: 8
...
Len: 1024, Cap: 1024
Len: 1025, Cap: 1280
```

## Practical Preallocation Examples

### Slice Preallocation

Without preallocation, each append operation might trigger new allocations:

```go
// Inefficient
var result []int
for i := 0; i < 10000; i++ {
    result = append(result, i)
}
```

This pattern causes Go to allocate larger underlying arrays repeatedly as the slice grows, resulting in memory copying and GC pressure. We can avoid that by using `make` with a specified capacity:

```go
// Efficient
result := make([]int, 0, 10000)
for i := 0; i < 10000; i++ {
    result = append(result, i)
}
```

### Map Preallocation

Maps grow similarly. By default, Go doesn’t know how many elements you’ll add, so it resizes the underlying structure as needed.

```go
// Inefficient
m := make(map[int]string)
for i := 0; i < 10000; i++ {
    m[i] = fmt.Sprintf("val-%d", i)
}
```

Starting with Go 1.11, you can preallocate `map` capacity too:

```go
// Efficient
m := make(map[int]string, 10000)
for i := 0; i < 10000; i++ {
    m[i] = fmt.Sprintf("val-%d", i)
}
```

This helps the runtime allocate enough internal storage upfront, avoiding rehashing and resizing costs.

## Benchmarking Impact

Here’s a simple benchmark comparing appending to a preallocated slice vs. a zero-capacity slice:

```go
func BenchmarkAppendNoPrealloc(b *testing.B) {
    for i := 0; i < b.N; i++ {
        var s []int
        for j := 0; j < 10000; j++ {
            s = append(s, j)
        }
    }
}

func BenchmarkAppendWithPrealloc(b *testing.B) {
    for i := 0; i < b.N; i++ {
        s := make([]int, 0, 10000)
        for j := 0; j < 10000; j++ {
            s = append(s, j)
        }
    }
}
```

You’ll typically observe that preallocation reduces allocations to a single one per operation and significantly improves throughput.

```
BenchmarkAppendNoPrealloc-14               41727             28539 ns/op          357626 B/op         19 allocs/op
BenchmarkAppendWithPrealloc-14            170154              7093 ns/op           81920 B/op          1 allocs/op
```

### When To Preallocate

Preallocation should be leveraged when the final size of your slices or maps can be reasonably anticipated, especially within loops or high-frequency operations. In such scenarios, preallocation leads to fewer memory allocations, reduced garbage collection overhead, and improved predictability.

However, preallocation isn’t universally beneficial. When dealing with unpredictable or widely varying data sizes, aggressive preallocation can cause unnecessary memory consumption. It may also result in over-provisioned memory, especially problematic in concurrent systems managing numerous large buffers simultaneously. As with all optimizations, profiling your application is essential to confirm that preallocation effectively addresses your performance constraints without introducing new issues.

