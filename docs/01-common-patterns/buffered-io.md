# Efficient Buffering in Go

Buffering is a core performance technique in systems programming. In Go, it's especially relevant when working with I/O—file access, network communication, and stream processing. Without buffering, many operations incur excessive system calls or synchronization overhead. Proper buffering reduces the frequency of such interactions, improves throughput, and smooths latency spikes.

## Why Buffering Matters

Every read or write to a file or socket may invoke a syscall or context switch. System calls involve a costly transition from user space (where your application runs) into kernel space (managed by the operating system). This overhead includes kernel mode entry, potential context switching, disk buffering, and queuing of write operations. By aggregating data in memory and writing or reading in chunks, buffered operations dramatically reduce the frequency and cost of these syscalls.

For example, writing to a file in a loop without buffering, like this:

```go
f, _ := os.Create("output.txt")
for i := 0; i < 10000; i++ {
    f.Write([]byte("line\n"))
}
```

results in **10,000 separate system calls**, greatly increasing overhead and slowing down your application. Additionally, repeated small writes fragment disk operations, placing unnecessary strain on system resources.

### With Buffering

```go
f, _ := os.Create("output.txt")
buf := bufio.NewWriter(f)
for i := 0; i < 10000; i++ {
    buf.WriteString("line\n")
}
buf.Flush() // ensure all buffered data is written
```

This version significantly reduces the number of system calls. The `bufio.Writer` accumulates writes in an internal memory buffer (typically 4KB or more). It only triggers a syscall when the buffer is full or explicitly flushed. As a result, you achieve faster I/O, reduced CPU usage, and improved performance.

!!! note
    `bufio.Writer` does not automatically flush when closed. If you forget to call `Flush()`, any unwritten data remaining in the buffer will be lost. Always call `Flush()` before closing or returning from a function, especially if the total written size is smaller than the buffer capacity.

### Controlling Buffer Capacity

By default, `bufio.NewWriter()` allocates a 4096-byte (4 KB) buffer. This size aligns with the common block size of file systems and the standard memory page size on most operating systems (such as Linux, BSD, and macOS). Reading or writing in 4 KB increments minimizes page faults, aligns with kernel read-ahead strategies, and maps efficiently onto underlying disk I/O operations.

While 4 KB is a practical general-purpose default, it might not be optimal for all workloads. For high-throughput scenarios—such as streaming large files or generating extensive logs—a larger buffer can help reduce syscall frequency further:

```go
f, _ := os.Create("output.txt")
buf := bufio.NewWriterSize(f, 16*1024) // 16 KB buffer
```

Conversely, if latency is more critical than throughput (e.g., interactive systems or command-line utilities), a smaller buffer may be more appropriate, as it flushes data more frequently.

Similar logic applies when reading data:

```go
reader := bufio.NewReaderSize(f, 32*1024) // 32 KB buffer for input
```

Choosing buffer sizes should always be guided by profiling and empirical performance testing. Factors like disk type (SSD vs. HDD), file system configurations, CPU cache sizes, and overall system load can influence optimal buffer sizing.

## Benchmarking Impact

Buffered writes and reads consistently demonstrate significant performance gains under load. Benchmarks measuring system calls, memory allocations, and CPU usage typically show that buffered I/O operations are faster and more efficient than unbuffered counterparts. For example, writing one million lines to disk might exhibit up to an order-of-magnitude improvement using `bufio.Writer` compared to direct `os.File.Write()` calls. The more structured and bursty your I/O operations, the more substantial the benefits from buffering.

??? example "Show the benchmark file"
    ```go
    {% include "01-common-patterns/src/buffered-io_test.go" %}
    ```

Results:

| Benchmark                     | Iterations    | Time per op (ns) | Bytes per op | Allocs per op |
|-------------------------------|------|------------------|---------------|----------------|
| BenchmarkWriteNotBuffered-14 | 49   | 23,672,792       | 53,773        | 10,007         |
| BenchmarkWriteBuffered-14    | 3241 | 379,703          | 70,127        | 10,008         |

## When To Buffer

:material-checkbox-marked-circle-outline: Use buffering when:

- Performing frequent, small-sized I/O operations. Buffering groups small writes or reads into larger batches, which reduces the overhead of each individual operation.
- Reducing syscall overhead is crucial. Fewer syscalls mean lower context-switching costs and improved performance, especially in I/O-heavy applications.
- High throughput is more important than minimal latency. Buffered I/O can increase total data processed per second, even if it introduces slight delays in delivery.

:fontawesome-regular-hand-point-right: Avoid buffering when:

- Immediate data availability and low latency are critical. Buffers introduce delays by design, which can be unacceptable in real-time or interactive systems.
- Buffering excessively might lead to uncontrolled memory usage. Without limits or proper flushing, buffers can grow large and put pressure on system memory.