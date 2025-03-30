# Zero-Copy Techniques

Managing memory wisely can make a noticeable difference when writing performance-critical Go code. Zero-copy techniques are particularly effective because they avoid unnecessary memory copying by directly manipulating data buffers. By doing so, these techniques significantly enhance throughput and reduce latency, making them highly beneficial for applications that handle intensive I/O operations.

## Understanding Zero-Copy

Traditionally, reading or writing data involves copying between user-space buffers and kernel-space buffers, incurring CPU and memory overhead. Zero-copy techniques bypass these intermediate copying steps, allowing applications to access and process data directly from the underlying buffers. This approach significantly reduces CPU load, memory bandwidth, and latency.

## Common Zero-Copy Techniques in Go

### Using `io.Reader` and `io.Writer` Interfaces

Leveraging interfaces such as `io.Reader` and `io.Writer` can facilitate efficient buffer reuse and minimize copying:

```go
func StreamData(src io.Reader, dst io.Writer) error {
	buf := make([]byte, 4096) // Reusable buffer
	_, err := io.CopyBuffer(dst, src, buf)
	return err
}
```

`io.CopyBuffer` reuses a provided buffer, avoiding repeated allocations and intermediate copies. An in-depth `io.CopyBuffer` explanation is [available on SO](https://stackoverflow.com/questions/71082021/what-exactly-is-buffer-last-parameter-in-io-copybuffer).

### Slicing for Efficient Data Access

Slicing large byte arrays or buffers instead of copying data into new slices is a powerful zero-copy strategy:

```go
func process(buffer []byte) []byte {
	return buffer[128:256] // returns a slice reference without copying
}
```

Slices in Go are inherently zero-copy since they reference the underlying array.

### Memory Mapping (`mmap`)

Using memory mapping enables direct access to file contents without explicit read operations:

```go
import "golang.org/x/exp/mmap"

func ReadFileZeroCopy(path string) ([]byte, error) {
	r, err := mmap.Open(path)
	if err != nil {
		return nil, err
	}
	defer r.Close()

	data := make([]byte, r.Len())
	_, err = r.ReadAt(data, 0)
	return data, err
}
```

This approach maps file contents directly into memory, entirely eliminating copying between kernel and user-space.

## Benchmarking Impact

Here's a basic benchmark illustrating performance differences between explicit copying and zero-copy slicing:


```go
{%
    include-markdown "01-common-patterns/src/zero-copy_test.go"
    start="// bench-start"
    end="// bench-end"
%}
```

In `BenchmarkCopy`, a 64KB buffer is copied into a new slice during every iteration, incurring both memory allocation and data copy overhead. In contrast, `BenchmarkSlice` simply re-slices the same buffer without any allocation or copying. This demonstrates how zero-copy operations like slicing can vastly outperform traditional copying under load.

!!! info
	These two functions are not equivalent in behavior—`BenchmarkCopy` makes an actual deep copy of the buffer, while `BenchmarkSlice` only creates a new slice header pointing to the same underlying data. This benchmark is not comparing functional correctness but is intentionally contrasting performance characteristics to highlight the cost of unnecessary copying.

	| Benchmark                | Time per op (ns) | Bytes per op | Allocs per op |
	|--------------------------|---------|--------|------------|
	| BenchmarkCopy            | 4,246   | 65536 | 1          |
	| BenchmarkSlice           | 0.592   | 0     | 0          |


### File I/O: Memory Mapping vs. Standard Read

We also benchmarked file reading performance using `os.ReadAt` versus `mmap.Open` for a 4MB binary file.

```go
{%
    include-markdown "01-common-patterns/src/zero-copy_test.go"
    start="// bench-io-start"
    end="// bench-io-end"
%}
```

??? info "How to run the benchmark"
	To run the benchmark involving `mmap`, you’ll need to install the required package and create a test file:

	```bash
	go get golang.org/x/exp/mmap
	mkdir -p testdata
	dd if=/dev/urandom of=./testdata/largefile.bin bs=1M count=4
	```

Benchmark Results

| Benchmark                | Time per op (ns) | Bytes per op | Allocs per op |
|--------------------------|---------|------|------------|
| ReadWithCopy             | 94,650  | 0    | 0          |
| ReadWithMmap             | 50,082  | 0    | 0          |

The memory-mapped version (`mmap`) is nearly 2× faster than the standard read call. This illustrates how zero-copy access through memory mapping can substantially reduce read latency and CPU usage for large files.

??? example "Show the complete benchmark file"
    ```go
    {% include "01-common-patterns/src/interface-boxing_test.go" %}
    ```

## When to Use Zero-Copy

:material-checkbox-marked-circle-outline: Zero-copy techniques are highly beneficial for:

- Network servers handling large amounts of concurrent data streams. Avoiding unnecessary memory copies helps reduce CPU usage and latency, especially under high load.
- Applications with heavy I/O operations like file streaming or real-time data processing. Zero-copy allows data to move through the system efficiently without redundant allocations or copies.

!!! warning
	:fontawesome-regular-hand-point-right: Zero-copy should be used judiciously. Since slices share underlying memory, care must be taken to prevent unintended data mutations. Shared memory can lead to subtle bugs if one part of the system modifies data still in use elsewhere. Zero-copy can also introduce additional complexity, so it’s important to measure and confirm that the performance gains are worth the tradeoffs.

### Real-World Use Cases and Libraries

Zero-copy strategies aren't just theoretical—they're used in production by performance-critical Go systems:

- [fasthttp](https://github.com/valyala/fasthttp): A high-performance HTTP server designed to avoid allocations. It returns slices directly and avoids `string` conversions to minimize copying.
- [gRPC-Go](https://github.com/grpc/grpc-go): Uses internal buffer pools and avoids deep copying of large request/response messages to reduce GC pressure.
- [MinIO](https://github.com/minio/minio): An object storage system that streams data directly between disk and network using `io.Reader` without unnecessary buffer replication.
- [Protobuf](https://github.com/protocolbuffers/protobuf) and [MsgPack](https://github.com/vmihailenco/msgpack) libraries: Efficient serialization frameworks like `google.golang.org/protobuf` and `vmihailenco/msgpack` support decoding directly into user-managed buffers.
- [InfluxDB](https://github.com/influxdata/influxdb) and [Badger](https://github.com/hypermodeinc/badger): These storage engines use `mmap` extensively for fast, zero-copy access to database files.

These libraries show how zero-copy techniques help reduce allocations, GC overhead, and system call frequency—all while increasing throughput.
