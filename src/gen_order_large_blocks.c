#include <stdio.h>
#include <stdlib.h>

#define TOTAL_SIZE 1048576u
#define HALF_SIZE 524288u
#define OUT_PATH "generated/order/order_large_blocks.bin"

int main(void)
{
	unsigned char *data = malloc(TOTAL_SIZE);
	FILE *fp;

	if (data == NULL) {
		fprintf(stderr, "allocation failed\n");
		return 1;
	}

	for (size_t i = 0; i < TOTAL_SIZE; i++) {
		data[i] = (i < HALF_SIZE) ? 'A' : 'B';
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
