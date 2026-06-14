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
              const float* __restrict__ src, float* __restrict__ dest)
{
  namespace cg = cooperative_groups;
  cg::thread_block block = cg::this_thread_block();
  cg::thread_block_tile<32> warp = cg::tiled_partition<32>(block);
  int i = blockIdx.x * warp.meta_group_size() + warp.meta_group_rank();
  if (i >= numSlice) return;

  const float* slice_src = src + i * sliceSize;
  float* slice_dst = dest + i * sliceSize;

  // Pass 1: online max+sum in a single sweep (saves one full read of src)
  float max_ = -3.402823466e+38f;
  float sum = 0.0f;

  if (sliceSize % 4 == 0) {
    const float4* src4 = reinterpret_cast<const float4*>(slice_src);
    const int n4 = sliceSize >> 2;
    #pragma unroll 4
    for (int j = warp.thread_rank(); j < n4; j += warp.size()) {
      float4 v = __ldg(&src4[j]);
      float local_max = max(max(v.x, v.y), max(v.z, v.w));
      float new_max = max(max_, local_max);
      float scale = expf(max_ - new_max);
      sum = sum * scale + expf(v.x - new_max) + expf(v.y - new_max)
                        + expf(v.z - new_max) + expf(v.w - new_max);
      max_ = new_max;
    }
  } else {
    for (int j = warp.thread_rank(); j < sliceSize; j += warp.size()) {
      float x = __ldg(&slice_src[j]);
      float new_max = max(max_, x);
      sum = sum * expf(max_ - new_max) + expf(x - new_max);
      max_ = new_max;
    }
  }

  // Warp reduce (max_, sum) pairs using butterfly shuffle
  #pragma unroll
  for (int offset = 16; offset > 0; offset >>= 1) {
    float other_max = __shfl_xor_sync(0xffffffff, max_, offset);
    float other_sum = __shfl_xor_sync(0xffffffff, sum, offset);
    float new_max = max(max_, other_max);
    sum = sum * expf(max_ - new_max) + other_sum * expf(other_max - new_max);
    max_ = new_max;
  }

  // Pass 2: write output
  const float inv_sum = 1.0f / sum;
  if (sliceSize % 4 == 0) {
    const float4* src4 = reinterpret_cast<const float4*>(slice_src);
    float4* dst4 = reinterpret_cast<float4*>(slice_dst);
    const int n4 = sliceSize >> 2;
    #pragma unroll 4
    for (int j = warp.thread_rank(); j < n4; j += warp.size()) {
      float4 v = __ldg(&src4[j]);
      float4 out;
      out.x = expf(v.x - max_) * inv_sum;
      out.y = expf(v.y - max_) * inv_sum;
      out.z = expf(v.z - max_) * inv_sum;
      out.w = expf(v.w - max_) * inv_sum;
      __stcs(&dst4[j], out);
    }
  } else {
    for (int j = warp.thread_rank(); j < sliceSize; j += warp.size()) {
      slice_dst[j] = expf(__ldg(&slice_src[j]) - max_) * inv_sum;
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
