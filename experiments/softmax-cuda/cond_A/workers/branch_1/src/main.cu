#include <chrono>
#include <cstdlib>
#include <cstdio>
#include <cfloat>
#include <cuda.h>
#include <cooperative_groups.h>
#include <cooperative_groups/reduce.h>

#define BLOCK_SIZE 256
#define WARPS_PER_BLOCK (BLOCK_SIZE / 32)
#define SMEM_LIMIT_BYTES 49152

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

// Warp-per-slice softmax: eliminates double expf by staging exp values through dest.
// When sliceSize % 4 == 0, uses float4 vectorized loads/stores to reduce instruction
// count by 4x per pass and cut memory stall events proportionally.
// Pass 1: read src (float4), compute warp max.
// Pass 2: read src (float4), compute expf once each, write to dest (float4), sum.
// Pass 3: read dest (L2-hot, float4), normalize in place, write dest (float4).
// Scalar fallback for sliceSize not divisible by 4.
__global__
void softMax2 (const int numSlice, const int sliceSize,
              const float* src, float* dest)
{
  namespace cg = cooperative_groups;
  cg::thread_block block = cg::this_thread_block();
  cg::thread_block_tile<32> warp = cg::tiled_partition<32>(block);
  int i = blockIdx.x * warp.meta_group_size() + warp.meta_group_rank();
  if (i >= numSlice) return;

  int base = i * sliceSize;

  if ((sliceSize & 3) == 0) {
    int vc = sliceSize >> 2;  // number of float4 elements per slice
    const float4* src4 = reinterpret_cast<const float4*>(src + base);
    float4* dest4 = reinterpret_cast<float4*>(dest + base);

    // Pass 1: float4 loads, find warp max
    float max_ = -FLT_MAX;
    for (int j = warp.thread_rank(); j < vc; j += warp.size()) {
      float4 v = src4[j];
      max_ = max(max_, max(max(v.x, v.y), max(v.z, v.w)));
    }
    max_ = cg::reduce(warp, max_, cg::greater<float>{});

    // Pass 2: float4 loads, compute expf, float4 stores to dest, accumulate sum
    float sum = 0;
    for (int j = warp.thread_rank(); j < vc; j += warp.size()) {
      float4 v = src4[j];
      float4 e;
      e.x = expf(v.x - max_); e.y = expf(v.y - max_);
      e.z = expf(v.z - max_); e.w = expf(v.w - max_);
      dest4[j] = e;
      sum += e.x + e.y + e.z + e.w;
    }
    sum = cg::reduce(warp, sum, cg::plus<float>{});

    // Pass 3: float4 load from L2-hot dest, normalize, float4 store
    for (int j = warp.thread_rank(); j < vc; j += warp.size()) {
      float4 v = dest4[j];
      v.x /= sum; v.y /= sum; v.z /= sum; v.w /= sum;
      dest4[j] = v;
    }
  } else {
    // Scalar fallback for non-multiple-of-4 sliceSize
    float max_ = -FLT_MAX;
    for (int j = warp.thread_rank(); j < sliceSize; j += warp.size()) {
      max_ = max(max_, src[base + j]);
    }
    max_ = cg::reduce(warp, max_, cg::greater<float>{});

    float sum = 0;
    for (int j = warp.thread_rank(); j < sliceSize; j += warp.size()) {
      float e = expf(src[base + j] - max_);
      dest[base + j] = e;
      sum += e;
    }
    sum = cg::reduce(warp, sum, cg::plus<float>{});

    for (int j = warp.thread_rank(); j < sliceSize; j += warp.size()) {
      dest[base + j] /= sum;
    }
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
