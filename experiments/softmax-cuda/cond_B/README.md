# CUDA Kernel Optimization Request: softmax-cuda

You are a CUDA optimization expert. A separate Claude Code Worker will execute each ranked plan for exactly 7 iterations.

Propose exactly five distinct optimization plans and rank them by which starting direction is most likely to achieve the highest peak speedup at any point within those 7 iterations. Consider how the first direction opens or blocks later optimizations.

## First: Inspect And Measure

Before writing plans:

1. Inspect the copied kernel source in `planner/src/`.
2. Run the benchmark/profile command:

```bash
./benchmark.sh
```

3. Read these outputs when present:

```text
planner/out/run.json
```

Use the source and measured results to decide the ranked plans. Do not edit files in `planner/src/`; this step is for planning only.

## Output File

Write your answer to exactly this file:

```text
response.json
```

Do not write any other files.

## Required JSON Format

`response.json` must be a JSON array of exactly five objects. Each object may contain only these two fields:

```json
[
  {
    "rank": 1,
    "plan": "Specific optimization plan..."
  }
]
```

Rules:

- Include exactly five plans.
- Ranks must be integers 1 through 5 with no duplicates.
- Lower rank means higher priority.
- Each `plan` must be specific enough to implement directly.
- Each `plan` should include high-level steps, target bottleneck, what to be careful about, and correctness/performance risks.
- Do not include extra fields like name, id, files_to_modify, explanation, or estimated speedup.

## Kernel

`softmax-cuda`

## Editable Files

Only consider changes to these files:

```text
main.cu
```

## Reconnaissance Notes

- Makefile naive command with implementation 0 failed correctness on RTX 3080 Ti.
- Use implementation 1 as the softmax experiment target.
- Problem size increased to 600000 slices to exceed 5 ms.

## Profiling Digest

```text
Baseline digest is not captured yet. Use source and reconnaissance notes only.
```

## Source Snapshot

A copied source tree is available in `planner/src/`. The allowlisted files are also shown below for convenience.

## Source: `main.cu`

```cuda
#include <chrono>
#include <cstdlib>
#include <cstdio>
#include <cuda.h>
#include <cooperative_groups.h>
#include <cooperative_groups/reduce.h>

#define BLOCK_SIZE 256

// A C model derived from the OpenCL kernel
void softMax_cpu(const int numSlice, const int sliceSize, const float* src, float* dest) {
  for (int i = 0; i < numSlice; i++) {
    float max_ = src[i * sliceSize];
    for (int j = 0; j < sliceSize; j++) {
      max_ = (max_ < src[i * sliceSize + j]) ? src[i * sliceSize + j] : max_;
    }
    float sum = 0;
    for (int j = 0; j < sliceSize; j++) {
      float e = expf(src[i * sliceSize + j] - max_);
      sum += e;
      dest[i * sliceSize + j] = e;
    }
    for (int j = 0; j < sliceSize; j++) {
      dest[i * sliceSize + j] /= sum;
    }
  }
}

__global__
void softMax (const int numSlice, const int sliceSize,
              const float* src, float* dest)
{
  int i = blockIdx.x * blockDim.x + threadIdx.x;
  if (i >= numSlice) return;
  float max_ = src[i * sliceSize];
  for (int j = 0; j < sliceSize; j++) {
    max_ = max(max_, src[i * sliceSize + j]);
  }
  float sum = 0;
  for (int j = 0; j < sliceSize; j++) {
    sum += expf(src[i * sliceSize + j] - max_);
  }
  for (int j = 0; j < sliceSize; j++) {
    dest[i * sliceSize + j] = expf(src[i * sliceSize + j] - max_) / sum;
  }
}

__global__
void softMax2 (const int numSlice, const int sliceSize,
              const float* src, float* dest)
{
  namespace cg = cooperative_groups;
  cg::thread_block block = cg::this_thread_block();
  cg::thread_block_tile<32> warp = cg::tiled_partition<32>(block);
  int i = blockIdx.x * warp.meta_group_size() + warp.meta_group_rank();
  if (i >= numSlice) return;
  float max_ = src[i * sliceSize];
  for (int j = warp.thread_rank(); j < sliceSize; j += warp.size()) {
    max_ = max(max_, src[i * sliceSize + j]);
  }
  max_ = cg::reduce(warp, max_, cg::greater<float>{});
  float sum = 0;
  for (int j = warp.thread_rank(); j < sliceSize; j += warp.size()) {
    sum += expf(src[i * sliceSize + j] - max_);
  }
  sum = cg::reduce(warp, sum, cg::plus<float>{});
  for (int j = warp.thread_rank(); j < sliceSize; j += warp.size()) {
    dest[i * sliceSize + j] = expf(src[i * sliceSize + j] - max_) / sum;
  }
}


int main(int argc, char* argv[]) {
  if (argc != 5) {
    printf("Usage: %s <number of slices> <slice size> <implementations> <repeat>\n", argv[0]);
    printf("implementation 0: naive\n");
    printf("implementation 1: optimized\n");
    return 1;
  }

  int numSlice = atoi(argv[1]);
  int sliceSize = atoi(argv[2]);
  int kernel = atoi(argv[3]);
  int repeat = atoi(argv[4]);
  int numElem = numSlice * sliceSize;

  float* input = (float*) aligned_alloc(1024, sizeof(float) * numElem);
  float* output_gpu = (float*) aligned_alloc(1024, sizeof(float) * numElem);
  float* output_cpu = (float*) aligned_alloc(1024, sizeof(float) * numElem);

  srand(2);
  for (int i = 0; i < numSlice; i++)
    for (int j = 0; j < sliceSize; j++)
      input[i*sliceSize+j] = rand() % 13;

  float *d_input, *d_output;
  cudaMalloc((void**)&d_input, sizeof(float) * numElem);
  cudaMalloc((void**)&d_output, sizeof(float) * numElem);
  cudaMemcpy(d_input, input, sizeof(float) * numElem, cudaMemcpyHostToDevice);

  if (kernel == 1) {
    dim3 grids ((numSlice+BLOCK_SIZE/32-1)/(BLOCK_SIZE/32));
    dim3 blocks (BLOCK_SIZE);

    cudaDeviceSynchronize();
    auto start = std::chrono::steady_clock::now();

    for (int n = 0; n < repeat; n++) {
      softMax2<<<grids, blocks>>>(numSlice, sliceSize, d_input, d_output);
    }

    cudaDeviceSynchronize();
    auto end = std::chrono::steady_clock::now();
    auto time = std::chrono::duration_cast<std::chrono::nanoseconds>(end - start).count();
    printf("Average kernel execution time: %f (ms)\n", (time * 1e-6f) / repeat);
  }
  else {
    dim3 grids ((numSlice+BLOCK_SIZE-1)/BLOCK_SIZE);
    dim3 blocks (BLOCK_SIZE);

    cudaDeviceSynchronize();
    auto start = std::chrono::steady_clock::now();

    for (int n = 0; n < repeat; n++) {
      softMax<<<grids, blocks>>>(numSlice, sliceSize, d_input, d_output);
    }

    cudaDeviceSynchronize();
    auto end = std::chrono::steady_clock::now();
    auto time = std::chrono::duration_cast<std::chrono::nanoseconds>(end - start).count();
    printf("Average kernel execution time: %f (ms)\n", (time * 1e-6f) / repeat);
  }

  cudaMemcpy(output_gpu, d_output, sizeof(float) * numElem, cudaMemcpyDeviceToHost);

  // verification
  bool ok = true;
  softMax_cpu(numSlice, sliceSize, input, output_cpu);
  for (int i = 0; i < numElem; i++) {
    if (fabsf(output_cpu[i] - output_gpu[i]) > 1e-3) {
      printf("@index %d host: %f device: %f\n", i, output_cpu[i], output_gpu[i]);
      ok = false;
      break;
    }
  }
  printf("%s\n", ok ? "PASS" : "FAIL");

  free(input);
  free(output_cpu);
  free(output_gpu);
  cudaFree(d_input);
  cudaFree(d_output);
  return 0;
}

```
