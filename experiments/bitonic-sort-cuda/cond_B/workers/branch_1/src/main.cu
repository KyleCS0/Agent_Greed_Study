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

// Use BLOCK_SIZE=512 so that tile = 2*BLOCK_SIZE = 1024 ints = 4KB shared memory per block
#define BLOCK_SIZE 512

// Global-memory bitonic sort kernel for large stages (seq_len > 2*BLOCK_SIZE).
// Launched with size/2 threads (not size), each thread handles exactly one pair.
// Conflict-free mapping: thread tid maps to lo = (tid/h_len)*seq_len + (tid%h_len), hi = lo+h_len.
// This gives 100% load efficiency (no wasted threads).
__global__
void bitonic_sort(const int stage, const int two_power, int *a)
{
  const int tid = blockDim.x * blockIdx.x + threadIdx.x;  // tid in [0, size/2)
  const int h_len = 1 << stage;
  const int seq_len = h_len << 1;

  // Conflict-free mapping: each thread handles exactly one pair
  const int lo = ((tid >> stage) * seq_len) + (tid & (h_len - 1));
  const int hi = lo + h_len;

  // Use right-shifts instead of division for power-of-2 divisors
  const int s_num = lo >> (stage + 1);       // lo / seq_len
  const int log2_two_power = step - stage;   // two_power = 2^(step-stage)
  const int odd = s_num >> log2_two_power;   // s_num / two_power
  const bool increasing = ((odd & 1) == 0);

  const int a_lo = a[lo];
  const int a_hi = a[hi];
  if (((a_lo > a_hi) && increasing) || ((a_lo < a_hi) && !increasing)) {
    a[lo] = a_hi;
    a[hi] = a_lo;
  }
}

// Fused shared-memory kernel: processes multiple stages (from stage_start down to 0)
// where all seq_len <= 2*BLOCK_SIZE (i.e., all stages fit within one tile).
//
// Each block handles a tile of 2*BLOCK_SIZE elements.
// BLOCK_SIZE threads, each responsible for exactly ONE compare-swap pair per stage.
//
// Hybrid approach:
//   - Stages 5..stage_start (seq_len=64..tile_size): use shared memory + __syncthreads()
//   - Stages 0..4 (seq_len=2..32, warp-local): use register-level operations with __syncwarp()
//     Each thread holds its TWO tile elements in registers and performs warp shuffles.
//
// For warp-local stages: thread tid (0..BLOCK_SIZE-1) holds two values:
//   reg0 = element at tile position tid
//   reg1 = element at tile position tid + BLOCK_SIZE
// After shared-memory stages, write smem back to registers, then process warp stages,
// then write back to global memory.
//
// Note: warp-local approach requires each thread to hold 2 registers across 5 stages.
// For stage k (h_len=2^k <= 16), the swap partner within the warp can be found with
// __shfl_xor_sync using mask = h_len.
__global__
void bitonic_sort_fused(const int step, const int stage_start, const int total_size, int *a)
{
  extern __shared__ int smem[];

  const int tile_size = blockDim.x * 2;  // = 2*BLOCK_SIZE
  const int tile_base = blockIdx.x * tile_size;
  const int tid = threadIdx.x;

  // Load tile into shared memory (2 elements per thread, coalesced)
  const int idx0 = tile_base + tid;
  const int idx1 = tile_base + tid + blockDim.x;

  smem[tid]              = a[idx0];
  smem[tid + blockDim.x] = a[idx1];

  __syncthreads();

  // Process shared-memory stages (stage_start down to 5, seq_len >= 64)
  // For stage < 5 (seq_len < 64 = 2*warp_size), switch to warp-shuffle approach
  const int smem_min_stage = 5;  // min stage handled in smem (seq_len >= 64)

  for (int stage = stage_start; stage >= smem_min_stage; stage--) {
    const int seq_len   = 1 << (stage + 1);
    const int two_power = 1 << (step - stage);
    const int h_len     = seq_len >> 1;

    // Conflict-free mapping
    const int lo = ((tid >> stage) * seq_len) + (tid & (h_len - 1));
    const int hi = lo + h_len;

    const int global_seq = (tile_base + lo) >> (stage + 1);  // (tile_base+lo) / seq_len
    const int odd        = global_seq >> (step - stage);     // global_seq / two_power
    const bool increasing = ((odd & 1) == 0);

    const int a_lo = smem[lo];
    const int a_hi = smem[hi];
    if (((a_lo > a_hi) && increasing) || ((a_lo < a_hi) && !increasing)) {
      smem[lo] = a_hi;
      smem[hi] = a_lo;
    }
    __syncthreads();
  }

  // Load tile elements into registers for warp-shuffle stages
  // Thread tid holds reg0 (tile pos tid) and reg1 (tile pos tid+BLOCK_SIZE)
  int reg0 = smem[tid];
  int reg1 = smem[tid + blockDim.x];

  const int lane    = tid & 31;  // lane within warp (0..31)
  const int warp_id = tid >> 5;  // warp index within block

  // Warp base tile positions
  const int wbase0 = warp_id << 5;               // lane 0 of this warp, lower tile half
  const int wbase1 = (warp_id << 5) + blockDim.x; // lane 0 of this warp, upper tile half

  // Process warp-local stages (stage 4 down to 0, seq_len=32..2)
  // For each stage k (h_len = 2^k <= 16, seq_len = 2^(k+1) <= 32):
  //   All swap partners within this warp (since seq_len <= 32 elements).
  //   Partner = lane XOR h_len.
  //   Use __shfl_xor_sync to get partner value.
  //   Both lower and upper half threads update consistently:
  //     lower half (lane & h_len == 0): keep min if increasing, max if decreasing
  //     upper half (lane & h_len != 0): keep max if increasing, min if decreasing
  #pragma unroll
  for (int stage = (smem_min_stage - 1); stage >= 0; stage--) {
    const int h_len     = 1 << stage;
    const int seq_len   = h_len << 1;
    const int two_power = 1 << (step - stage);
    const unsigned mask_all = 0xFFFFFFFF;

    // --- Handle reg0 (lower tile half) ---
    {
      const int global_pos = tile_base + wbase0 + lane;
      const int s_num = global_pos >> (stage + 1);    // global_pos / seq_len
      const int odd = s_num >> (step - stage);         // s_num / two_power
      const bool increasing = ((odd & 1) == 0);
      const bool in_first_half = ((lane & h_len) == 0);

      const int partner = __shfl_xor_sync(mask_all, reg0, h_len);

      // Both lower and upper update: lower wants min/max depending on direction,
      // upper wants the complement.
      if (increasing) {
        reg0 = in_first_half ? min(reg0, partner) : max(reg0, partner);
      } else {
        reg0 = in_first_half ? max(reg0, partner) : min(reg0, partner);
      }
    }

    // --- Handle reg1 (upper tile half) ---
    {
      const int global_pos = tile_base + wbase1 + lane;
      const int s_num = global_pos >> (stage + 1);    // global_pos / seq_len
      const int odd = s_num >> (step - stage);         // s_num / two_power
      const bool increasing = ((odd & 1) == 0);
      const bool in_first_half = ((lane & h_len) == 0);

      const int partner = __shfl_xor_sync(mask_all, reg1, h_len);

      if (increasing) {
        reg1 = in_first_half ? min(reg1, partner) : max(reg1, partner);
      } else {
        reg1 = in_first_half ? max(reg1, partner) : min(reg1, partner);
      }
    }
    // No __syncthreads needed since operations are warp-local
    // __syncwarp() not needed since shfl_xor already implies warp sync
  }

  // Write back to global memory (coalesced)
  a[idx0] = reg0;
  a[idx1] = reg1;
}

void ParallelBitonicSort(int input[], int n) {

  int size = (int)pow(2, n);
  size_t size_bytes = sizeof(int) * size;

  int *d_input;
  cudaMalloc((void**)&d_input, size_bytes);
  cudaMemcpy(d_input, input, size_bytes, cudaMemcpyHostToDevice);

  // log2(BLOCK_SIZE): stages with stage <= log2_block can be fused
  // because seq_len = 2^(stage+1) <= 2*BLOCK_SIZE = tile_size
  // 2^(stage+1) <= 2*BLOCK_SIZE  =>  stage <= log2(BLOCK_SIZE) = log2_block
  int log2_block = 0;
  {
    int tmp = BLOCK_SIZE;
    while (tmp > 1) { tmp >>= 1; log2_block++; }
  }
  int fuse_max_stage = log2_block;  // = 9 for BLOCK_SIZE=512

  int tile_size = BLOCK_SIZE * 2;
  int smem_bytes = tile_size * (int)sizeof(int);
  int num_tiles = size / tile_size;

  auto start = std::chrono::steady_clock::now();

  for (int step = 0; step < n; step++) {
    // Handle large stages (seq_len > tile_size) with the global-memory kernel
    // Launch size/2 threads (one per compare-swap pair) for 100% efficiency
    for (int stage = step; stage > fuse_max_stage; stage--) {
      int two_power = 1 << (step - stage);
      bitonic_sort<<<(size/2) / BLOCK_SIZE, BLOCK_SIZE>>>(stage, two_power, d_input);
    }

    // Fuse remaining stages (stage_start = min(step, fuse_max_stage) down to 0)
    int stage_start = (step < fuse_max_stage) ? step : fuse_max_stage;
    bitonic_sort_fused<<<num_tiles, BLOCK_SIZE, smem_bytes>>>(step, stage_start, size, d_input);

  } // end step

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
    int odd = seq_num / (int)(pow(2, (step - stage)));
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
      int num_sequence = (int)pow(2, (n - stage - 1));
      int sequence_len = (int)pow(2, stage + 1);
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
    size = (int)pow(2, n);
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
