#include <stdio.h>
#include <stdlib.h>

// Author: calmadios, 2020
// License: MIT

int main()
{
	char ufs_string[29] = { 0x55, 0x6E, 0x69, 0x74, 0x79, 0x46, 0x53, 0x00,
							0x00, 0x00, 0x00, 0x06, 0x35, 0x2E, 0x78, 0x2E,
							0x78, 0x00, 0x32, 0x30, 0x31, 0x37, 0x2E, 0x34,
							0x2E, 0x32, 0x33, 0x66, 0x31 };
	int ufs_len = 29;
	int ufs_idx = 0;
	int c = 0;
	int sight = 0;
	int ccount = 0;

	while ((c = getchar()) != EOF && ++ccount < 512) {
		if (ufs_idx == ufs_len - 1) {
			++sight;
			if (sight == 2) {
				return 1;
			}
			ufs_idx = 0;
		}

		if (c == ufs_string[ufs_idx]) ++ufs_idx;
		else ufs_idx = 0;
	}

	return 0;
}
