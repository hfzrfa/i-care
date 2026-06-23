#ifndef CS_CONFIG_H
#define CS_CONFIG_H

static const int CS_N = 64;

static const int CS_M = 24;

static const uint32_t CS_SEED = 42;

static const uint32_t CS_SAMPLING_RATE_HZ = 100;

static const uint32_t CS_SAMPLE_DELAY_US = 1000000UL / CS_SAMPLING_RATE_HZ;

static float cs_phi[CS_M][CS_N];
static float cs_psi[CS_N][CS_N];
static float cs_dwt_coeffs[CS_N];

static float cs_gsr_buffer[CS_N];
static float cs_emg_buffer[CS_N];
static int   cs_buffer_index = 0;

static const uint32_t CS_LCG_A = 1103515245UL;
static const uint32_t CS_LCG_C = 12345UL;
static const float CS_LCG_DENOM = 2147483650.0f;
static uint32_t cs_lcg_state = CS_SEED;

static float cs_next_uniform() {
  cs_lcg_state = (CS_LCG_A * cs_lcg_state + CS_LCG_C) & 0x7FFFFFFFUL;
  return ((float)cs_lcg_state + 1.0f) / CS_LCG_DENOM;
}

static float cs_gaussian_random() {
  const float twoPi = 6.2831853071795864769f;
  float u1 = cs_next_uniform();
  float u2 = cs_next_uniform();

  
  float g = sqrtf(-2.0f * logf(u1)) * cosf(twoPi * u2);

  
  return g / sqrtf((float)CS_M);
}

static void cs_generate_measurement_matrix() {
  cs_lcg_state = CS_SEED;
  for (int i = 0; i < CS_M; i++) {
    for (int j = 0; j < CS_N; j++) {
      cs_phi[i][j] = cs_gaussian_random();
    }
  }
}

static void cs_generate_wavelet_basis() {
  const float invSqrtN = 1.0f / sqrtf((float)CS_N);
  for (int i = 0; i < CS_N; i++) {
    for (int j = 0; j < CS_N; j++) {
      cs_psi[i][j] = 0.0f;
    }
  }

  for (int i = 0; i < CS_N; i++) {
    cs_psi[i][0] = invSqrtN;
  }

  for (int k = 1; k < CS_N; k++) {
    int p = 0;
    while ((1 << (p + 1)) <= k) {
      p++;
    }
    const int q = k - (1 << p);
    const float factor = powf(2.0f, (float)p / 2.0f) / sqrtf((float)CS_N);
    const int block = CS_N >> p;
    const int start = q * block;
    const int mid = start + (block >> 1);
    const int end = start + block;

    for (int i = start; i < mid; i++) {
      cs_psi[i][k] = factor;
    }
    for (int i = mid; i < end; i++) {
      cs_psi[i][k] = -factor;
    }
  }
}

static void cs_forward_dwt(const float* x, float* coeffs) {
  for (int k = 0; k < CS_N; k++) {
    float sum = 0.0f;
    for (int i = 0; i < CS_N; i++) {
      sum += cs_psi[i][k] * x[i];
    }
    coeffs[k] = sum;
  }
}

static void cs_compress_signal(const float* x, float* y) {
  cs_forward_dwt(x, cs_dwt_coeffs);
  for (int i = 0; i < CS_M; i++) {
    float sum = 0.0f;
    for (int j = 0; j < CS_N; j++) {
      sum += cs_phi[i][j] * cs_dwt_coeffs[j];
    }
    y[i] = sum;
  }
}

#endif 
