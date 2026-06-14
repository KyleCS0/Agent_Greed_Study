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

#define BLOCK_SIZE 512
// SMEM_ELEMS = 2*BLOCK_SIZE elements per block
#define SMEM_ELEMS (2 * BLOCK_SIZE)
// SMEM_STAGE_LIMIT: SMEM_ELEMS=1024=2^10, stage+1<=10 => stage<=9
#define SMEM_STAGE_LIMIT 9

// Global-memory kernel for stages where seq_len > SMEM_ELEMS
// Each thread handles 2 comparisons (stride = total_threads) to improve MLP
__global__
void bitonic_sort(const int seq_len, const int two_power, int * __restrict__ a,
                  const int n_half)
{
  // Total comparisons = size/2; this kernel launches size/2/BLOCK_SIZE blocks
  // n_half = size/2; each thread handles one comparison at index i
  int i = blockDim.x * blockIdx.x + threadIdx.x;
  if (i >= n_half) return;

  // Determine position within bitonic sequence
  int seq_num  = i / (seq_len / 2);   // which bitonic sequence
  // Actual element index in the first half of seq_num's sequence
  int pos      = i - seq_num * (seq_len / 2);
  int elem_i   = seq_num * seq_len + pos;
  int elem_j   = elem_i + seq_len / 2;

  int odd = seq_num / two_power;
  bool increasing = ((odd & 1) == 0);

  int ai = a[elem_i];
  int aj = a[elem_j];
  if (((ai > aj) && increasing) || ((ai < aj) && !increasing)) {
    a[elem_i] = aj;
    a[elem_j] = ai;
  }
}

// Shared memory kernel: processes all stages from `from_stage` down to 0.
// Each block owns SMEM_ELEMS consecutive elements.
__global__
void bitonic_sort_shared(const int from_stage, const int step, int * __restrict__ a)
{
  __shared__ int s[SMEM_ELEMS];

  int tid  = threadIdx.x;
  int base = blockIdx.x * SMEM_ELEMS;

  s[tid]             = a[base + tid];
  s[tid + BLOCK_SIZE] = a[base + tid + BLOCK_SIZE];
  __syncthreads();

  for (int stage = from_stage; stage >= 0; stage--) {
    int h_len   = 1 << stage;
    int seq_len = h_len << 1;

    #pragma unroll 2
    for (int k = 0; k < 2; k++) {
      int i = tid + k * BLOCK_SIZE;
      int pos_in_seq = i & (seq_len - 1);
      if (pos_in_seq < h_len) {
        int j = i + h_len;
        int global_seq_num = (base + i) >> (stage + 1);
        int odd = global_seq_num >> (step - stage);
        bool increasing = ((odd & 1) == 0);

        int si = s[i], sj = s[j];
        if (((si > sj) && increasing) || ((si < sj) && !increasing)) {
          s[i] = sj;
          s[j] = si;
        }
      }
    }
    __syncthreads();
  }

  a[base + tid]             = s[tid];
  a[base + tid + BLOCK_SIZE] = s[tid + BLOCK_SIZE];
}

void ParallelBitonicSort(int input[], int n) {

  int size = 1 << n;
  size_t size_bytes = sizeof(int) * size;

  int *d_input;
  cudaMalloc((void**)&d_input, size_bytes);
  cudaMemcpy(d_input, input, size_bytes, cudaMemcpyHostToDevice);

  int n_half = size / 2;

  auto start = std::chrono::steady_clock::now();

  for (int step = 0; step < n; step++) {
    // Global kernel for stages > SMEM_STAGE_LIMIT
    // Launch size/2 threads; each does exactly one comparison
    for (int stage = step; stage > SMEM_STAGE_LIMIT; stage--) {
      int seq_len   = 1 << (stage + 1);
      int two_power = 1 << (step - stage);
      // n_half threads, BLOCK_SIZE per block
      bitonic_sort<<< n_half/BLOCK_SIZE, BLOCK_SIZE >>>(seq_len, two_power, d_input, n_half);
    }

    // Shared-memory kernel covering stages SMEM_STAGE_LIMIT..0
    int smem_from = (step <= SMEM_STAGE_LIMIT) ? step : SMEM_STAGE_LIMIT;
    bitonic_sort_shared<<< size / SMEM_ELEMS, BLOCK_SIZE >>>(smem_from, step, d_input);
  }

  cudaDeviceSynchronize();
  auto end = std::chrono::steady_clock::now();
  auto time = std::chrono::duration_cast<std::chrono::nanoseconds>(end - start).count();
  printf("Total kernel execution time: %f (ms)\n", time * 1e-6f);

  cudaMemcpy(input, d_input, size_bytes, cudaMemcpyDeviceToHost);
  cudaFree(d_input);
}

void SwapElements(int step, int stage, int num_sequence, int seq_len,
                  int *array) {
  for (int seq_num = 0; seq_num < num_sequence; seq_num++) {
    int odd = seq_num / (1 << (step - stage));
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
      int num_sequence = 1 << (n - stage - 1);
      int sequence_len = 1 << (stage + 1);
      SwapElements(step, stage, num_sequence, sequence_len, a);
    }
  }
}

void Usage(std::string prog_name, int exponent) {
  std::cout << " Incorrect parameters\n";
  std::cout << " Usage: " << prog_name << " n k \n\n";
  std::cout << " n: Integer exponent presenting the size of the input array. "
               "The number of element in\n";
  std::cout << "    the array must be power of 2 (e.g., 1, 2, 4, ...). Please "
               "enter the corresponding\n";
  std::cout << "    exponent between 0 and " << exponent - 1 << ".\n";
  std::cout << " k: Seed used to generate a random sequence.\n";
}

int main(int argc, char *argv[]) {
  int n, seed, size;
  int exp_max = log2(std::numeric_limits<int>::max());

  try {
    n = std::stoi(argv[1]);

    if (n < 0 || n >= exp_max) {
      Usage(argv[0], exp_max);
      return -1;
    }

    seed = std::stoi(argv[2]);
    size = 1 << n;
  } catch (...) {
    Usage(argv[0], exp_max);
    return -1;
  }

  std::cout << "\nArray size: " << size << ", seed: " << seed << "\n";

  size_t size_bytes = size * sizeof(int);

  int *data_cpu = (int *)malloc(size_bytes);
  int *data_gpu = (int *)malloc(size_bytes);

  srand(seed);

  for (int i = 0; i < size; i++) {
    data_gpu[i] = data_cpu[i] = rand() % 1000;
  }

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
