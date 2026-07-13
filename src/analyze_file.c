#include <inttypes.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>

#define BUFFER_SIZE 65536

int main(int argc, char **argv)
{
	FILE *fp;
	unsigned char buffer[BUFFER_SIZE];
	uint64_t counts[256] = {0};
	uint64_t total = 0;
	size_t n;
	double entropy = 0.0;

	if (argc != 2) {
		fprintf(stderr, "usage: analyze_file FILE\n");
		return 1;
	}

	fp = fopen(argv[1], "rb");
	if (fp == NULL) {
		fprintf(stderr, "failed to open file\n");
		return 1;
	}

	while ((n = fread(buffer, 1, sizeof(buffer), fp)) > 0) {
		size_t i;

		for (i = 0; i < n; i++) {
			counts[buffer[i]]++;
		}
		total += (uint64_t)n;
	}

	if (ferror(fp)) {
		fprintf(stderr, "failed to read file\n");
		fclose(fp);
		return 1;
	}

	fclose(fp);

	if (total == 0) {
		fprintf(stderr, "empty file\n");
		return 1;
	}

	for (int i = 0; i < 256; i++) {
		if (counts[i] > 0) {
			double p = (double)counts[i] / (double)total;
			entropy -= p * (log(p) / log(2.0));
		}
	}

	printf("%" PRIu64 ",%.9f\n", total, entropy);
	return 0;
}
