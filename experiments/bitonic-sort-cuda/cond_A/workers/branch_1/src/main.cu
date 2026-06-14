//==============================================================
// Copyright © 2020 Intel Corporation
//
// SPDX-License-Identifier: MIT
// =============================================================
//
// Bitonic Sort: this algorithm converts a randomized sequence of numbers into
// a bitonic sequence (two ordered sequences), and then merge these two ordered
// sequences into a ordered sequence.
//
#include <math.h>
#include <string.h>
#include <chrono>
#include <iostream>
#include <limits>
#include <cuda.h>

#define BLOCK_SIZE 256

// Original per-stage global-memory kernel (used for large seq_len stages)
__global__
void bitonic_sort (const int seq_len, const int two_power, int *a)
{
  int i = blockDim.x * blockIdx.x + threadIdx.x;
  int seq_num = i / seq_len;
  int swapped_ele = -1;
  int h_len = seq_len / 2;
  if (i < (seq_len * seq_num) + h_len) swapped_ele = i + h_len;
  int odd = seq_num / two_power;
  bool increasing = ((odd % 2) == 0);
  if (swapped_ele != -1) {
    if (((a[i] > a[swapped_ele]) && increasing) ||
	((a[i] < a[swapped_ele]) && !increasing)) {
      int temp = a[i];
      a[i] = a[swapped_ele];
      a[swapped_ele] = temp;
    }
  }
}

// Fused shared-memory kernel.
// Each block handles one tile of TILE = 2*BLOCK_SIZE elements.
// Executes all stages from stage_start down to 0 for the given step.
// Thread tid handles the tid-th compare-swap pair in the tile:
//   h_len = seq_len / 2
//   seq_in_tile = tid / h_len
//   pos_in_half = tid % h_len
//   local_i = seq_in_tile * seq_len + pos_in_half
//   local_j = local_i + h_len
__global__
void bitonic_sort_shared(const int step, const int stage_start, int *a)
{
    const int TILE = 2 * BLOCK_SIZE;
    int base = blockIdx.x * TILE;
    int tid  = threadIdx.x;

    __shared__ int smem[2 * BLOCK_SIZE];

    smem[tid]              = a[base + tid];
    smem[tid + BLOCK_SIZE] = a[base + tid + BLOCK_SIZE];
    __syncthreads();

    for (int stage = stage_start; stage >= 0; stage--) {
        int seq_len   = 1 << (stage + 1);
        int h_len     = seq_len >> 1;
        int two_power = 1 << (step - stage);

        int seq_in_tile  = tid / h_len;
        int pos_in_half  = tid % h_len;
        int local_i      = seq_in_tile * seq_len + pos_in_half;
        int local_j      = local_i + h_len;

        int global_seq_num = (base / seq_len) + seq_in_tile;
        int odd            = global_seq_num / two_power;
        bool increasing    = ((odd & 1) == 0);

        if (((smem[local_i] > smem[local_j]) && increasing) ||
            ((smem[local_i] < smem[local_j]) && !increasing)) {
            int temp      = smem[local_i];
            smem[local_i] = smem[local_j];
            smem[local_j] = temp;
        }
        __syncthreads();
    }

    a[base + tid]              = smem[tid];
    a[base + tid + BLOCK_SIZE] = smem[tid + BLOCK_SIZE];
}

void ParallelBitonicSort(int input[], int n) {
  int size = 1 << n;
  size_t size_bytes = sizeof(int) * size;

  int *d_input;
  cudaMalloc((void**)&d_input, size_bytes);
  cudaMemcpy(d_input, input, size_bytes, cudaMemcpyHostToDevice);

  auto start = std::chrono::steady_clock::now();

  // Stages where seq_len = 2^(stage+1) <= 2*BLOCK_SIZE fit in smem.
  // 2^(stage+1) <= 2*BLOCK_SIZE => stage <= log2(BLOCK_SIZE)
  // For BLOCK_SIZE=256: SMEM_STAGE_MAX = 8
  const int SMEM_STAGE_MAX = __builtin_ctz(BLOCK_SIZE); // 8
  const int TILE = 2 * BLOCK_SIZE;
  const int num_tiles = size / TILE;

  for (int step = 0; step < n; step++) {
    for (int stage = step; stage > SMEM_STAGE_MAX; stage--) {
      int seq_len   = 1 << (stage + 1);
      int two_power = 1 << (step - stage);
      bitonic_sort<<< size/BLOCK_SIZE, BLOCK_SIZE >>> (seq_len, two_power, d_input);
    }
    int smem_top = (step < SMEM_STAGE_MAX) ? step : SMEM_STAGE_MAX;
    bitonic_sort_shared<<< num_tiles, BLOCK_SIZE >>> (step, smem_top, d_input);
  }

  cudaDeviceSynchronize();
  auto end = std::chrono::steady_clock::now();
  auto time = std::chrono::duration_cast<std::chrono::nanoseconds>(end - start).count();
  printf("Total kernel execution time: %f (ms)\n", time * 1e-6f);

  cudaMemcpy(input, d_input, size_bytes, cudaMemcpyDeviceToHost);
  cudaFree(d_input);
}

void SwapElements(int step, int stage, int num_sequence, int seq_len, int *array) {
  for (int seq_num = 0; seq_num < num_sequence; seq_num++) {
    int odd = seq_num / (pow(2, (step - stage)));
    bool increasing = ((odd % 2) == 0);
    int h_len = seq_len / 2;
    for (int i = seq_num * seq_len; i < seq_num * seq_len + h_len; i++) {
      int swapped_ele = i + h_len;
      if (((array[i] > array[swapped_ele]) && increasing) ||
          ((array[i] < array[swapped_ele]) && !increasing)) {
        int temp = array[i];
        array[i] = array[swapped_ele];
        array[swapped_ele] = temp;
      }
    }
  }
}

inline void BitonicSort(int a[], int n) {
  for (int step = 0; step < n; step++) {
    for (int stage = step; stage >= 0; stage--) {
      int num_sequence = pow(2, (n - stage - 1));
      int sequence_len = pow(2, stage + 1);
      SwapElements(step, stage, num_sequence, sequence_len, a);
    }
  }
}

void Usage(std::string prog_name, int exponent) {
  std::cout << " Incorrect parameters\n";
  std::cout << " Usage: " << prog_name << " n k \n\n";
  std::cout << " n: Integer exponent presenting the size of the input array.\n";
  std::cout << " k: Seed used to generate a random sequence.\n";
}

int main(int argc, char *argv[]) {
  int n, seed, size;
  int exp_max = log2(std::numeric_limits<int>::max());
  try {
    n = std::stoi(argv[1]);
    if (n < 0 || n >= exp_max) { Usage(argv[0], exp_max); return -1; }
    seed = std::stoi(argv[2]);
    size = pow(2, n);
  } catch (...) { Usage(argv[0], exp_max); return -1; }

  std::cout << "\nArray size: " << size << ", seed: " << seed << "\n";
  size_t size_bytes = size * sizeof(int);
  int *data_cpu = (int *)malloc(size_bytes);
  int *data_gpu = (int *)malloc(size_bytes);
  srand(seed);
  for (int i = 0; i < size; i++) { data_gpu[i] = data_cpu[i] = rand() % 1000; }

  std::cout << "Bitonic sort (parallel)..\n";
  ParallelBitonicSort(data_gpu, n);
  std::cout << "Bitonic sort (serial)..\n";
  BitonicSort(data_cpu, n);

  int unequal = memcmp(data_gpu, data_cpu, size_bytes);
  std::cout << (unequal ? "FAIL" : "PASS") << std::endl;
  free(data_cpu);
  free(data_gpu);
  return 0;
}
