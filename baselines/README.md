# Baseline Notes

Baselines are treated as immutable once captured. The harness reads `baseline.json` for each kernel and compares all Worker iterations against that original median runtime.

Current recorded setup:

- HecBench commit: `f27000a5188f8ac79bd43fc95a1b3f890c18823d`
- GPU environment: CUDA/NVIDIA tools available on this machine
- `ncu`: installed; the harness tries passwordless `sudo -n ncu` for hardware counters
- `atomicReduction-cuda`: used as the reduction target in this HecBench commit

The harness still runs when `ncu` is blocked. It falls back to `nsys` timing and collects static compiler resource data with `nvcc -Xptxas=-v`.

To enable full `ncu` hardware counters, apply the NVIDIA profiling permission change outside the experiment run, then reboot:

```bash
sudo sh -c 'printf "options nvidia NVreg_RestrictProfilingToAdminUsers=0\n" > /etc/modprobe.d/nvidia-profiler.conf'
sudo update-initramfs -u
sudo reboot
```

Baseline files:

```text
baselines/<kernel>/baseline.json
baselines/<kernel>/reference_output.txt      # gitignored when generated
baselines/<kernel>/baseline_profile.csv      # gitignored when generated
baselines/<kernel>/baseline_digest.txt       # gitignored when generated
baselines/<kernel>/timing_raw.txt            # gitignored when generated
```

Do not recapture or edit baseline values during a real condition run.
