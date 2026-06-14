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
// - Step 0: for each pair (sequence of size 2), the two elements are swap so
// that the two consecutive pairs form  a bitonic sequence in increasing order,
// the next two pairs form the second bitonic sequence in decreasing order, the
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
#include <cooperative_groups.h>

namespace cg = cooperative_groups;

#define BLOCK_SIZE 256

// Persistent cooperative kernel: processes all steps/stages in one launch.
// Uses grid.sync() instead of separate kernel launches.
// Grid-stride loop handles the case where grid size < total_threads.
__global__
void bitonic_sort_persistent(const int n, const int size, int *a)
{
  cg::grid_group grid = cg::this_grid();
  int total_threads = size / 2; // only first half of each bitonic sequence needs to work

  // step from 0, 1, 2, ..., n-1
  for (int step = 0; step < n; step++) {
    // for each step s, stage goes s, s-1, ..., 0
    for (int stage = step; stage >= 0; stage--) {
      // seq_len = 2^(stage+1), h_len = 2^stage
      int h_len_log2 = stage;          // log2(h_len) = stage
      int seq_len_log2 = stage + 1;    // log2(seq_len) = stage+1
      int h_len = 1 << h_len_log2;     // h_len = seq_len/2
      int two_power_log2 = step - stage; // log2(two_power)

      // Grid-stride loop: each thread handles multiple elements if grid is smaller
      for (int i = blockDim.x * blockIdx.x + threadIdx.x;
           i < total_threads;
           i += blockDim.x * gridDim.x) {

        // seq_num = i / h_len (h_len is power of 2, so use shift)
        int seq_num = i >> h_len_log2;
        int local_i = i & (h_len - 1);  // i % h_len (h_len is power of 2)
        int idx = (seq_num << seq_len_log2) + local_i;
        int swapped_ele = idx + h_len;

        // Check whether increasing or decreasing order.
        // odd = seq_num / two_power = seq_num >> two_power_log2
        int odd = seq_num >> two_power_log2;
        bool increasing = ((odd & 1) == 0);

        // Branchless swap using min/max
        int va = a[idx];
        int vb = a[swapped_ele];
        int lo = min(va, vb);
        int hi = max(va, vb);
        // increasing: store lo at idx, hi at swapped_ele
        // decreasing: store hi at idx, lo at swapped_ele
        a[idx]        = increasing ? lo : hi;
        a[swapped_ele] = increasing ? hi : lo;
      }

      // All threads must sync before next stage
      grid.sync();
    }  // end stage
  } // end step
}

void ParallelBitonicSort(int input[], int n) {

  // n: the exponent used to set the array size. Array size = power(2, n)
  int size = pow(2, n);
  size_t size_bytes = sizeof(int) * size;

  int *d_input;
  cudaMalloc((void**)&d_input, size_bytes);
  cudaMemcpy(d_input, input, size_bytes, cudaMemcpyHostToDevice);

  // Determine max blocks for cooperative launch
  int device;
  cudaGetDevice(&device);
  int max_blocks_per_sm;
  cudaOccupancyMaxActiveBlocksPerMultiprocessor(&max_blocks_per_sm,
      bitonic_sort_persistent, BLOCK_SIZE, 0);
  int num_sm;
  cudaDeviceGetAttribute(&num_sm, cudaDevAttrMultiProcessorCount, device);
  int max_blocks = max_blocks_per_sm * num_sm;

  // We need at least 1 block, at most size/BLOCK_SIZE blocks
  int full_blocks = size / BLOCK_SIZE;
  int num_blocks = (max_blocks < full_blocks) ? max_blocks : full_blocks;
  if (num_blocks < 1) num_blocks = 1;

  void *args[] = { &n, &size, &d_input };

  auto start = std::chrono::steady_clock::now();

  cudaLaunchCooperativeKernel((void*)bitonic_sort_persistent,
                               num_blocks, BLOCK_SIZE,
                               args, 0, 0);

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
