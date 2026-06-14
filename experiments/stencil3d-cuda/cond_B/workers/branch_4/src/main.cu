#include <stdio.h>
#include <stdlib.h>
#include <chrono>
#include <cuda.h>

// 2D block size
#define BSIZE 16
// Tile size in the x direction
#define XTILE 20

typedef double Real;

__global__ void stencil3d(
    const Real*__restrict__ d_psi,
          Real*__restrict__ d_npsi,
    const Real*__restrict__ d_sigmaX,
    const Real*__restrict__ d_sigmaY,
    const Real*__restrict__ d_sigmaZ,
    int nx, int ny, int nz)
{

  // z is the fastest varying direction
  // Pad z-dim by 8 to shift bank offsets between y-rows, reducing 4-way to 2-way bank conflicts
  __shared__ Real sm_psi[4][BSIZE][BSIZE+8];

  #define V0(y,z) sm_psi[pii][y][z]
  #define V1(y,z) sm_psi[cii][y][z]
  #define V2(y,z) sm_psi[nii][y][z]

  #define sigmaX(x,y,z,dir) d_sigmaX[ z + nz * ( y + ny * ( x + nx * dir ) ) ]
  #define sigmaY(x,y,z,dir) d_sigmaY[ z + nz * ( y + ny * ( x + nx * dir ) ) ]
  #define sigmaZ(x,y,z,dir) d_sigmaZ[ z + nz * ( y + ny * ( x + nx * dir ) ) ]

  #define psi(x,y,z) d_psi[ z + nz * ( (y) + ny * (x) ) ]
  #define npsi(x,y,z) d_npsi[ z + nz * ( (y) + ny * (x) ) ]

  const int tjj = threadIdx.y;
  // Thread coarsening in z: each thread handles two z-points
  const int tkk_lo = threadIdx.x;           // 0 .. BSIZE/2-1
  const int tkk_hi = threadIdx.x + BSIZE/2; // BSIZE/2 .. BSIZE-1

  // shift for each tile by updating device pointers
  d_psi = &(psi(XTILE*blockIdx.x, (BSIZE-2)*blockIdx.y, (BSIZE-2)*blockIdx.z));
  d_npsi = &(npsi(XTILE*blockIdx.x, (BSIZE-2)*blockIdx.y, (BSIZE-2)*blockIdx.z));

  d_sigmaX = &(sigmaX(XTILE*blockIdx.x, (BSIZE-2)*blockIdx.y, (BSIZE-2)*blockIdx.z, 0));
  d_sigmaY = &(sigmaY(XTILE*blockIdx.x, (BSIZE-2)*blockIdx.y, (BSIZE-2)*blockIdx.z, 0));
  d_sigmaZ = &(sigmaZ(XTILE*blockIdx.x, (BSIZE-2)*blockIdx.y, (BSIZE-2)*blockIdx.z, 0));

  int nLast_x=XTILE+1; int nLast_y=(BSIZE-1); int nLast_z=(BSIZE-1);
  if (blockIdx.x == gridDim.x-1) nLast_x = nx-2 - XTILE * blockIdx.x + 1;
  if (blockIdx.y == gridDim.y-1) nLast_y = ny-2 - (BSIZE-2) * blockIdx.y + 1;
  if (blockIdx.z == gridDim.z-1) nLast_z = nz-2 - (BSIZE-2) * blockIdx.z + 1;

  // Exit if both z-points are out of range (tkk_lo is always <= tkk_hi)
  if (tjj > nLast_y || tkk_lo > nLast_z) return;
  const bool have_hi = (tkk_hi <= nLast_z);

  // previous, current, next, and temp indices
  int pii,cii,nii,tii;
  pii=0; cii=1; nii=2;

  // Load initial slices for lo (always) and hi (if in bounds)
  sm_psi[cii][tjj][tkk_lo] = psi(0,tjj,tkk_lo);
  sm_psi[nii][tjj][tkk_lo] = psi(1,tjj,tkk_lo);
  if (have_hi) {
    sm_psi[cii][tjj][tkk_hi] = psi(0,tjj,tkk_hi);
    sm_psi[nii][tjj][tkk_hi] = psi(1,tjj,tkk_hi);
  }

  Real dV_lo = 0, dV_hi = 0;

  __syncthreads();

  // initial x-face contribution at x=1, for lo and hi
  if ((tkk_lo>0) && (tkk_lo<nLast_z) && (tjj>0) && (tjj<nLast_y))
  {
    Real xd=-V1(tjj,tkk_lo) + V2(tjj,tkk_lo);
    Real yd=(-V1(-1+tjj,tkk_lo) + V1(1+tjj,tkk_lo) - V2(-1+tjj,tkk_lo) + V2(1+tjj,tkk_lo))/4.;
    Real zd=(-V1(tjj,-1+tkk_lo) + V1(tjj,1+tkk_lo) - V2(tjj,-1+tkk_lo) + V2(tjj,1+tkk_lo))/4.;
    dV_lo -= sigmaX(1,tjj,tkk_lo,0)*xd + sigmaX(1,tjj,tkk_lo,1)*yd + sigmaX(1,tjj,tkk_lo,2)*zd;
  }
  if (have_hi && (tkk_hi>0) && (tkk_hi<nLast_z) && (tjj>0) && (tjj<nLast_y))
  {
    Real xd=-V1(tjj,tkk_hi) + V2(tjj,tkk_hi);
    Real yd=(-V1(-1+tjj,tkk_hi) + V1(1+tjj,tkk_hi) - V2(-1+tjj,tkk_hi) + V2(1+tjj,tkk_hi))/4.;
    Real zd=(-V1(tjj,-1+tkk_hi) + V1(tjj,1+tkk_hi) - V2(tjj,-1+tkk_hi) + V2(tjj,1+tkk_hi))/4.;
    dV_hi -= sigmaX(1,tjj,tkk_hi,0)*xd + sigmaX(1,tjj,tkk_hi,1)*yd + sigmaX(1,tjj,tkk_hi,2)*zd;
  }

  tii=pii; pii=cii; cii=nii; nii=tii;

  for(int ii=1;ii<nLast_x;ii++)
  {
    // Load next x-slice for lo and hi
    sm_psi[nii][tjj][tkk_lo] = psi(ii+1,tjj,tkk_lo);
    if (have_hi) sm_psi[nii][tjj][tkk_hi] = psi(ii+1,tjj,tkk_hi);
    __syncthreads();

    // y face current: lo
    if ((tkk_lo>0) && (tkk_lo<nLast_z) && (tjj<nLast_y))
    {
      Real xd=(-V0(tjj,tkk_lo) - V0(1+tjj,tkk_lo) + V2(tjj,tkk_lo) + V2(1+tjj,tkk_lo))/4.;
      Real yd=-V1(tjj,tkk_lo) + V1(1+tjj,tkk_lo);
      Real zd=(-V1(tjj,-1+tkk_lo) + V1(tjj,1+tkk_lo) - V1(1+tjj,-1+tkk_lo) + V1(1+tjj,1+tkk_lo))/4.;
      Real ycharge = sigmaY(ii,tjj+1,tkk_lo,0)*xd + sigmaY(ii,tjj+1,tkk_lo,1)*yd + sigmaY(ii,tjj+1,tkk_lo,2)*zd;
      dV_lo += ycharge;
      sm_psi[3][tjj][tkk_lo] = ycharge;
    }
    // y face current: hi
    if (have_hi && (tkk_hi>0) && (tkk_hi<nLast_z) && (tjj<nLast_y))
    {
      Real xd=(-V0(tjj,tkk_hi) - V0(1+tjj,tkk_hi) + V2(tjj,tkk_hi) + V2(1+tjj,tkk_hi))/4.;
      Real yd=-V1(tjj,tkk_hi) + V1(1+tjj,tkk_hi);
      Real zd=(-V1(tjj,-1+tkk_hi) + V1(tjj,1+tkk_hi) - V1(1+tjj,-1+tkk_hi) + V1(1+tjj,1+tkk_hi))/4.;
      Real ycharge = sigmaY(ii,tjj+1,tkk_hi,0)*xd + sigmaY(ii,tjj+1,tkk_hi,1)*yd + sigmaY(ii,tjj+1,tkk_hi,2)*zd;
      dV_hi += ycharge;
      sm_psi[3][tjj][tkk_hi] = ycharge;
    }
    __syncthreads();

    // Subtract y-face from left neighbor: lo and hi
    if ((tkk_lo>0) && (tkk_lo<nLast_z) && (tjj>0) && (tjj<nLast_y))
      dV_lo -= sm_psi[3][tjj-1][tkk_lo];
    if (have_hi && (tkk_hi>0) && (tkk_hi<nLast_z) && (tjj>0) && (tjj<nLast_y))
      dV_hi -= sm_psi[3][tjj-1][tkk_hi];
    __syncthreads();

    // z face current: lo
    if ((tkk_lo<nLast_z) && (tjj>0) && (tjj<nLast_y))
    {
      Real xd=(-V0(tjj,tkk_lo) - V0(tjj,1+tkk_lo) + V2(tjj,tkk_lo) + V2(tjj,1+tkk_lo))/4.;
      Real yd=(-V1(-1+tjj,tkk_lo) - V1(-1+tjj,1+tkk_lo) + V1(1+tjj,tkk_lo) + V1(1+tjj,1+tkk_lo))/4.;
      Real zd=-V1(tjj,tkk_lo) + V1(tjj,1+tkk_lo);
      Real zcharge = sigmaZ(ii,tjj,tkk_lo+1,0)*xd + sigmaZ(ii,tjj,tkk_lo+1,1)*yd + sigmaZ(ii,tjj,tkk_lo+1,2)*zd;
      dV_lo += zcharge;
      sm_psi[3][tjj][tkk_lo] = zcharge;
    }
    // z face current: hi
    if (have_hi && (tkk_hi<nLast_z) && (tjj>0) && (tjj<nLast_y))
    {
      Real xd=(-V0(tjj,tkk_hi) - V0(tjj,1+tkk_hi) + V2(tjj,tkk_hi) + V2(tjj,1+tkk_hi))/4.;
      Real yd=(-V1(-1+tjj,tkk_hi) - V1(-1+tjj,1+tkk_hi) + V1(1+tjj,tkk_hi) + V1(1+tjj,1+tkk_hi))/4.;
      Real zd=-V1(tjj,tkk_hi) + V1(tjj,1+tkk_hi);
      Real zcharge = sigmaZ(ii,tjj,tkk_hi+1,0)*xd + sigmaZ(ii,tjj,tkk_hi+1,1)*yd + sigmaZ(ii,tjj,tkk_hi+1,2)*zd;
      dV_hi += zcharge;
      sm_psi[3][tjj][tkk_hi] = zcharge;
    }

    __syncthreads();

    // Subtract z-face from lower z neighbor: lo and hi
    if ((tkk_lo>0) && (tkk_lo<nLast_z) && (tjj>0) && (tjj<nLast_y))
      dV_lo -= sm_psi[3][tjj][tkk_lo-1];
    if (have_hi && (tkk_hi>0) && (tkk_hi<nLast_z) && (tjj>0) && (tjj<nLast_y))
      dV_hi -= sm_psi[3][tjj][tkk_hi-1];
    __syncthreads();

    // x face current + store: lo
    if ((tkk_lo>0) && (tkk_lo<nLast_z) && (tjj>0) && (tjj<nLast_y))
    {
      Real xd=-V1(tjj,tkk_lo) + V2(tjj,tkk_lo);
      Real yd=(-V1(-1+tjj,tkk_lo) + V1(1+tjj,tkk_lo) - V2(-1+tjj,tkk_lo) + V2(1+tjj,tkk_lo))/4.;
      Real zd=(-V1(tjj,-1+tkk_lo) + V1(tjj,1+tkk_lo) - V2(tjj,-1+tkk_lo) + V2(tjj,1+tkk_lo))/4.;
      Real xcharge = sigmaX(ii+1,tjj,tkk_lo,0)*xd + sigmaX(ii+1,tjj,tkk_lo,1)*yd + sigmaX(ii+1,tjj,tkk_lo,2)*zd;
      dV_lo += xcharge;
      npsi(ii,tjj,tkk_lo) = dV_lo;
      dV_lo = -xcharge;
    }
    // x face current + store: hi
    if (have_hi && (tkk_hi>0) && (tkk_hi<nLast_z) && (tjj>0) && (tjj<nLast_y))
    {
      Real xd=-V1(tjj,tkk_hi) + V2(tjj,tkk_hi);
      Real yd=(-V1(-1+tjj,tkk_hi) + V1(1+tjj,tkk_hi) - V2(-1+tjj,tkk_hi) + V2(1+tjj,tkk_hi))/4.;
      Real zd=(-V1(tjj,-1+tkk_hi) + V1(tjj,1+tkk_hi) - V2(tjj,-1+tkk_hi) + V2(tjj,1+tkk_hi))/4.;
      Real xcharge = sigmaX(ii+1,tjj,tkk_hi,0)*xd + sigmaX(ii+1,tjj,tkk_hi,1)*yd + sigmaX(ii+1,tjj,tkk_hi,2)*zd;
      dV_hi += xcharge;
      npsi(ii,tjj,tkk_hi) = dV_hi;
      dV_hi = -xcharge;
    }
    __syncthreads();
    tii=pii; pii=cii; cii=nii; nii=tii;
  }
}

int main(int argc, char* argv[])
{
  if (argc != 3) {
    printf("Usage: %s <grid dimension> <repeat>\n", argv[0]);
    return 1;
  }
  const int size = atoi(argv[1]);
  const int repeat = atoi(argv[2]);
  const int nx = size;
  const int ny = size;
  const int nz = size;
  const int vol = nx * ny * nz;
  printf("Grid dimension: nx=%d ny=%d nz=%d\n",nx,ny,nz);

  Real *d_Vm, *d_dVm, *d_sigma;

  // allocate and initialize Vm
  cudaMalloc((void**)&d_Vm, sizeof(Real)*vol);
  Real *h_Vm = (Real*) malloc (sizeof(Real)*vol);

#define h_Vm(x,y,z) h_Vm[ z + nz * ( y + ny * ( x  ) ) ]

  for(int ii=0;ii<nx;ii++)
    for(int jj=0;jj<ny;jj++)
      for(int kk=0;kk<nz;kk++)
        h_Vm(ii,jj,kk) = (ii*(ny*nz) + jj * nz + kk) % 19;

  cudaMemcpy(d_Vm, h_Vm, sizeof(Real) * vol , cudaMemcpyHostToDevice);

  // allocate and initialize sigma
  cudaMalloc((void**)&d_sigma,sizeof(Real)*vol*9);
  Real *h_sigma = (Real*) malloc(sizeof(Real)*vol*9);

  for (int i = 0; i < vol*9; i++) h_sigma[i] = i % 19;

  cudaMemcpy(d_sigma, h_sigma, sizeof(Real) * vol*9, cudaMemcpyHostToDevice);

  // reset dVm
  cudaMalloc((void**)&d_dVm,sizeof(Real)*vol);
  cudaMemset(d_dVm, 0, sizeof(Real) * vol);

  //determine block sizes
  int bdimz = (nz-2)/(BSIZE-2) + ((nz-2)%(BSIZE-2)==0?0:1);
  int bdimy = (ny-2)/(BSIZE-2) + ((ny-2)%(BSIZE-2)==0?0:1);
  int bdimx = (nx-2)/XTILE + ((nx-2)%XTILE==0?0:1);

  dim3 grids (bdimx, bdimy, bdimz);
  // Halve thread count in z: each thread handles two z-points (lo and hi)
  dim3 blocks (BSIZE/2, BSIZE, 1);

  cudaDeviceSynchronize();
  auto start = std::chrono::steady_clock::now();

  for (int i = 0; i < repeat; i++)
    stencil3d <<< grids, blocks >>> (
       d_Vm, d_dVm, d_sigma, d_sigma + 3*vol, d_sigma + 6*vol, nx, ny, nz);

  cudaDeviceSynchronize();
  auto end = std::chrono::steady_clock::now();
  auto time = std::chrono::duration_cast<std::chrono::nanoseconds>(end - start).count();
  printf("Average kernel execution time: %f (s)\n", (time * 1e-9f) / repeat);

  // read dVm
  Real *h_dVm = (Real*) malloc (sizeof(Real) * vol);
  cudaMemcpy(h_dVm, d_dVm, vol*sizeof(Real), cudaMemcpyDeviceToHost);

#ifdef DUMP
  for(int ii=0;ii<nx;ii++)
    for(int jj=0;jj<ny;jj++)
      for(int kk=0;kk<nz;kk++)
        printf("dVm (%d,%d,%d)=%e\n",ii,jj,kk,h_dVm[kk+nz*(jj+ny*ii)]);
#endif

  cudaFree(d_Vm);
  cudaFree(d_dVm);
  cudaFree(d_sigma);
  free(h_sigma);
  free(h_Vm);
  free(h_dVm);

  return 0;
}
