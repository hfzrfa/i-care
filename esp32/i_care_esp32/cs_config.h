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

static float cs_gaussian_random() {
  
  const float denom = (float)RAND_MAX + 1.0f;
  float u1 = ((float)rand() + 1.0f) / (denom + 1.0f);
  float u2 = ((float)rand() + 1.0f) / (denom + 1.0f);

  
  float g = sqrtf(-2.0f * logf(u1)) * cosf(2.0f * M_PI * u2);

  
  return g / sqrtf((float)CS_M);
}

static void cs_generate_measurement_matrix() {
  srand(CS_SEED);
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
