#include <chrono>
#include <cstdlib>
#include <cstdio>
#include <cuda.h>

#define BLOCK_SIZE 256
#define NUM_WARPS (BLOCK_SIZE / 32)

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

// Block-per-slice, BLOCK_SIZE=256, unrolled loops + smem exp-cache.
// Combines: loop unrolling (lower registers, better ILP) + exp-cache (no bank conflicts, halves expf).
__global__
void softMax2 (const int numSlice, const int sliceSize,
              const float* __restrict__ src, float* __restrict__ dest)
{
  __shared__ float warp_buf[NUM_WARPS];
  extern __shared__ float exp_cache[];

  int slice = blockIdx.x;
  if (slice >= numSlice) return;

  int tid = threadIdx.x;
  int warp_id = tid >> 5;
  int lane_id = tid & 31;

  const float* slice_src = src + slice * sliceSize;
  float* slice_dst = dest + slice * sliceSize;

  // Pass 1: find max
  float max_ = -3.402823466e+38f;
  #pragma unroll 4
  for (int j = tid; j < sliceSize; j += BLOCK_SIZE)
    max_ = max(max_, slice_src[j]);

  for (int offset = 16; offset > 0; offset >>= 1)
    max_ = max(max_, __shfl_down_sync(0xffffffff, max_, offset));

  if (lane_id == 0) warp_buf[warp_id] = max_;
  __syncthreads();

  if (warp_id == 0) {
    float val = (lane_id < NUM_WARPS) ? warp_buf[lane_id] : -3.402823466e+38f;
    for (int offset = NUM_WARPS >> 1; offset > 0; offset >>= 1)
      val = max(val, __shfl_down_sync(0xffffffff, val, offset));
    if (lane_id == 0) warp_buf[0] = val;
  }
  __syncthreads();

  float global_max = warp_buf[0];

  // Pass 2: expf to exp_cache, accumulate sum
  float sum = 0.0f;
  #pragma unroll 4
  for (int j = tid; j < sliceSize; j += BLOCK_SIZE) {
    float e = expf(slice_src[j] - global_max);
    exp_cache[j] = e;
    sum += e;
  }

  for (int offset = 16; offset > 0; offset >>= 1)
    sum += __shfl_down_sync(0xffffffff, sum, offset);

  if (lane_id == 0) warp_buf[warp_id] = sum;
  __syncthreads();

  if (warp_id == 0) {
    float val = (lane_id < NUM_WARPS) ? warp_buf[lane_id] : 0.0f;
    for (int offset = NUM_WARPS >> 1; offset > 0; offset >>= 1)
      val += __shfl_down_sync(0xffffffff, val, offset);
    if (lane_id == 0) warp_buf[0] = val;
  }
  __syncthreads();

  float global_sum = warp_buf[0];

  // Pass 3: normalize from smem, write output (no global src read, no expf)
  #pragma unroll 4
  for (int j = tid; j < sliceSize; j += BLOCK_SIZE)
    slice_dst[j] = exp_cache[j] / global_sum;
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
    dim3 grids (numSlice);
    dim3 blocks (BLOCK_SIZE);
    int smem_bytes = sliceSize * sizeof(float);

    cudaDeviceSynchronize();
    auto start = std::chrono::steady_clock::now();

    for (int n = 0; n < repeat; n++) {
      softMax2<<<grids, blocks, smem_bytes>>>(numSlice, sliceSize, d_input, d_output);
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
