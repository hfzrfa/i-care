#ifndef CS_CONFIG_H
#define CS_CONFIG_H

static const int CS_N = 64;

static const int CS_M = 24;

static const uint32_t CS_SEED = 42;

static const uint32_t CS_SAMPLING_RATE_HZ = 100;

static const uint32_t CS_SAMPLE_DELAY_US = 1000000UL / CS_SAMPLING_RATE_HZ;

static float cs_phi[CS_M][CS_N];

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

static void cs_compress_signal(const float* x, float* y) {
  for (int i = 0; i < CS_M; i++) {
    float sum = 0.0f;
    for (int j = 0; j < CS_N; j++) {
      sum += cs_phi[i][j] * x[j];
    }
    y[i] = sum;
  }
}

#endif 
