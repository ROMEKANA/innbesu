#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#define TOTAL_SIZE 1048576u
#define OUT_PATH "generated/random/random_1mib.bin"

static uint32_t rng_state = 0x9e3779b9u;

static uint32_t xorshift32(void)
{
	uint32_t x = rng_state;

	x ^= x << 13;
	x ^= x >> 17;
	x ^= x << 5;
	rng_state = x;
	return x;
}

int main(void)
{
	unsigned char *data = malloc(TOTAL_SIZE);
	FILE *fp;

	if (data == NULL) {
		fprintf(stderr, "allocation failed\n");
		return 1;
	}

	for (size_t i = 0; i < TOTAL_SIZE; i++) {
		data[i] = (unsigned char)(i % 256u);
	}

	for (size_t i = TOTAL_SIZE - 1; i > 0; i--) {
		size_t j = (size_t)(xorshift32() % (uint32_t)(i + 1));
		unsigned char t = data[i];
		data[i] = data[j];
		data[j] = t;
	}

	fp = fopen(OUT_PATH, "wb");
	if (fp == NULL || fwrite(data, 1, TOTAL_SIZE, fp) != TOTAL_SIZE) {
		fprintf(stderr, "write failed\n");
		free(data);
		if (fp != NULL) {
			fclose(fp);
		}
		return 1;
	}

	fclose(fp);
	free(data);
	return 0;
}
