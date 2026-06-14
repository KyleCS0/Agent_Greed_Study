//==============================================================
// Copyright © 2020 Intel Corporation
//
// SPDX-License-Identifier: MIT
// =============================================================
//
// Bitonic Sort: this algorithm converts a randomized sequence of numbers into
// a bitonic sequence (two ordered sequences), and then merge these two ordered
// sequences into a ordered sequence. Bitonic sort algorithm is briefly
// described as followed:
//
// - First, it decomposes the randomized sequence of size 2**n into 2**(n-1)
// pairs where each pair consists of 2 consecutive elements. Note that each pair
// is a bitonic sequence.
// - Step 0: for each pair (sequence of size 2), the two elements are swapped so
// that the two consecutive pairs form  a bitonic sequence in increasing order,
// the next two pairs form the second bitonic sequence in decreasing order, the
// next two pairs form the second bitonic sequence in decreasing order, the
// next two pairs form the third bitonic sequence in  increasing order, etc, ...
// . At the end of this step, we have 2**(n-1) bitonic sequences of size 2, and
// they follow an order increasing, decreasing, increasing, .., decreasing.
// Thus, they form 2**(n-2) bitonic sequences of size 4.
// - Step 1: for each new 2**(n-2) bitonic sequences of size 4, (each new
// sequence consists of 2 consecutive previous sequences), it swaps the elements
// so that at the end of step 1, we have 2**(n-2) bitonic sequences of size 4,
// and they follow an order: increasing, decreasing, increasing, ...,
// decreasing. Thus, they form 2**(n-3) bitonic sequences of size 8.
// - Same logic applies until we reach the last step.
// - Step n: at this last step, we have one bitonic sequence of size 2**n. The
// elements in the sequence are swapped until we have a sequence in increasing
// order.
//
// In this implementation, a randomized sequence of size 2**n is given (n is a
// positive number). At each stage, a part of step, the host redefines the
// ordered sequenes and sends data to the kernel. The kernel swaps the elements
// accordingly in parallel.
//
#include <math.h>
#include <string.h>
#include <chrono>
#include <iostream>
#include <limits>
#include <cuda.h>

#define BLOCK_SIZE 256

// Kernel for stages where seq_len > 2*BLOCK_SIZE (large stages).
// Uses coalesced index computation: each thread handles one pair (i, j=i+h_len).
// Consecutive threads handle consecutive low-half indices within a sequence.
__global__
void bitonic_sort (const int seq_len, const int two_power, int *a)
{
  int half_idx = blockDim.x * blockIdx.x + threadIdx.x;

  // h_len is half the sequence length
  int h_len = seq_len / 2;

  // Restructured index computation for coalesced memory access:
  // Consecutive threads handle consecutive low-half indices within each sequence.
  int block_in_seq = half_idx / h_len;
  int pos_in_half  = half_idx % h_len;
  int i = block_in_seq * seq_len + pos_in_half;
  int j = i + h_len;

  // Assign the bitonic sequence number.
  int seq_num = block_in_seq;

  // Check whether increasing or decreasing order.
  int odd = seq_num / two_power;

  // Boolean variable used to determine "increasing" or
  // "decreasing" order.
  bool increasing = ((odd % 2) == 0);

  // Swap the elements in the bitonic sequence if needed
  if (((a[i] > a[j]) && increasing) ||
      ((a[i] < a[j]) && !increasing)) {
    int temp = a[i];
    a[i] = a[j];
    a[j] = temp;
  }
}

// Shared memory kernel: handles all stages from low_stage down to 0 for a given step.
// Each block processes one chunk of 2*BLOCK_SIZE elements in shared memory.
// low_stage: the highest stage handled by this kernel (seq_len = 2^(low_stage+1) <= 2*BLOCK_SIZE)
// step: current sorting step (determines the increasing/decreasing direction)
// low_stage_two_power: two_power value for the low_stage = 2^(step - low_stage)
__global__ __launch_bounds__(256, 4)
void bitonic_sort_smem(const int low_stage, const int step,
                       const int low_stage_two_power, int *a)
{
  extern __shared__ int smem[];

  int tid = threadIdx.x;
  int block_offset = blockIdx.x * (2 * BLOCK_SIZE);

  // Load two elements per thread into shared memory
  smem[tid]            = a[block_offset + tid];
  smem[tid + BLOCK_SIZE] = a[block_offset + tid + BLOCK_SIZE];
  __syncthreads();

  // Process stages from low_stage down to 0
  int two_power = low_stage_two_power;
  for (int stage = low_stage; stage >= 0; stage--) {
    int seq_len = 1 << (stage + 1);
    int h_len   = seq_len / 2;

    // Each thread handles one pair within shared memory
    int half_idx    = tid;
    int block_in_seq = half_idx / h_len;
    int pos_in_half  = half_idx % h_len;
    int i = block_in_seq * seq_len + pos_in_half;
    int j = i + h_len;

    int seq_num    = (block_offset / seq_len) + block_in_seq;
    int odd        = seq_num / two_power;
    bool increasing = ((odd % 2) == 0);

    if (((smem[i] > smem[j]) && increasing) ||
        ((smem[i] < smem[j]) && !increasing)) {
      int temp = smem[i];
      smem[i]  = smem[j];
      smem[j]  = temp;
    }
    __syncthreads();

    two_power <<= 1; // two_power doubles as stage decreases by 1: 2^(step-stage) -> 2^(step-(stage-1))
  }

  // Write back to global memory
  a[block_offset + tid]            = smem[tid];
  a[block_offset + tid + BLOCK_SIZE] = smem[tid + BLOCK_SIZE];
}

void ParallelBitonicSort(int input[], int n) {

  // n: the exponent used to set the array size. Array size = power(2, n)
  int size = pow(2, n);
  size_t size_bytes = sizeof(int) * size;

  int *d_input;
  cudaMalloc((void**)&d_input, size_bytes);
  cudaMemcpy(d_input, input, size_bytes, cudaMemcpyHostToDevice);

  auto start = std::chrono::steady_clock::now();

  // SMEM_LOG2 = log2(2*BLOCK_SIZE) - 1 = highest stage that fits in 2*BLOCK_SIZE elements
  // 2*BLOCK_SIZE = 512 elements, seq_len = 2^(stage+1) <= 512 means stage+1 <= 9, stage <= 8
  const int SMEM_STAGE_MAX = 8; // stage where seq_len = 2^9 = 512 = 2*BLOCK_SIZE

  // step from 0, 1, 2, ...., n-1
  for (int step = 0; step < n; step++) {
    // for each step s, stage goes s, s-1, ..., 0
    for (int stage = step; stage > SMEM_STAGE_MAX; stage--) {
      // Large stages: use coalesced global memory kernel
      int seq_len = 1 << (stage + 1);
      int two_power = 1 << (step - stage);
      bitonic_sort<<< size/(2*BLOCK_SIZE), BLOCK_SIZE >>> (seq_len, two_power, d_input);
    }

    // Handle stages SMEM_STAGE_MAX down to 0 using shared memory kernel
    // (or all stages if step <= SMEM_STAGE_MAX)
    int smem_top_stage = (step <= SMEM_STAGE_MAX) ? step : SMEM_STAGE_MAX;
    int smem_two_power = 1 << (step - smem_top_stage);
    int smem_bytes = 2 * BLOCK_SIZE * sizeof(int);
    bitonic_sort_smem<<< size/(2*BLOCK_SIZE), BLOCK_SIZE, smem_bytes >>>(
        smem_top_stage, step, smem_two_power, d_input);
  }

  cudaDeviceSynchronize();
  auto end = std::chrono::steady_clock::now();
  auto time = std::chrono::duration_cast<std::chrono::nanoseconds>(end - start).count();
  printf("Total kernel execution time: %f (ms)\n", time * 1e-6f);

  cudaMemcpy(input, d_input, size_bytes, cudaMemcpyDeviceToHost);
  cudaFree(d_input);
}

// Loop over the bitonic sequences at each stage in serial.
void SwapElements(int step, int stage, int num_sequence, int seq_len,
                  int *array) {
  for (int seq_num = 0; seq_num < num_sequence; seq_num++) {
    int odd = seq_num / (pow(2, (step - stage)));
    bool increasing = ((odd % 2) == 0);

    int h_len = seq_len / 2;

    // For all elements in a bitonic sequence, swap them if needed
    for (int i = seq_num * seq_len; i < seq_num * seq_len + h_len; i++) {
      int swapped_ele = i + h_len;

      if (((array[i] > array[swapped_ele]) && increasing) ||
          ((array[i] < array[swapped_ele]) && !increasing)) {
        int temp = array[i];
        array[i] = array[swapped_ele];
        array[swapped_ele] = temp;
      }
    }  // end for all elements in a sequence
  }    // end all sequences
}

// Function sorts an array in serial using bitonic sort algorithm. The size of
// the array is indicated by the exponent n: the array size is 2 ** n.
inline void BitonicSort(int a[], int n) {
  // n: the exponent indicating the array size = 2 ** n.

  // step from 0, 1, 2, ...., n-1
  for (int step = 0; step < n; step++) {
    // for each step s, stage goes s, s-1,..., 0
    for (int stage = step; stage >= 0; stage--) {
      // Sequences (same size) are formed at each stage.
      int num_sequence = pow(2, (n - stage - 1));
      // The length of the sequences (2, 4, ...).
      int sequence_len = pow(2, stage + 1);

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

  // Read parameters.
  try {
    n = std::stoi(argv[1]);

    // Verify the boundary of acceptance.
    if (n < 0 || n >= exp_max) {
      Usage(argv[0], exp_max);
      return -1;
    }

    seed = std::stoi(argv[2]);
    size = pow(2, n);
  } catch (...) {
    Usage(argv[0], exp_max);
    return -1;
  }

  std::cout << "\nArray size: " << size << ", seed: " << seed << "\n";

  size_t size_bytes = size * sizeof(int);

  // Memory allocated for host access only.
  int *data_cpu = (int *)malloc(size_bytes);

  // Memory allocated to store gpu results
  int *data_gpu = (int *)malloc(size_bytes);

  // Initialize the array randomly using a seed.
  srand(seed);

  for (int i = 0; i < size; i++) {
    data_gpu[i] = data_cpu[i] = rand() % 1000;
  }

  std::cout << "Bitonic sort (parallel)..\n";
  ParallelBitonicSort(data_gpu, n);


  std::cout << "Bitonic sort (serial)..\n";
  BitonicSort(data_cpu, n);

  // Verify
  int unequal = memcmp(data_gpu, data_cpu, size_bytes);
  std::cout << (unequal ? "FAIL" : "PASS") << std::endl;

  // Clean CPU memory.
  free(data_cpu);
  free(data_gpu);

  return 0;
}
