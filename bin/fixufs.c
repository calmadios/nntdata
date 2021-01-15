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
	int ufssp = 0;
	int ft = 0;
	int c = 0;
	char ucbuf[512];
	int ucbp = 0;
	int uc_idx = 0;
	int sight = 0;

	while ((c = getchar()) != EOF) {
		if (ft == 1) {
			putchar(c);
			continue;
		}

		if (ufs_idx == ufs_len - 1) {
			++sight;
			if (sight == 2) {
				ft = 1;
				while (ufssp < ufs_len) putchar(ufs_string[ufssp++]);
			}
			ufs_idx = 0;
		}

		if (c == ufs_string[ufs_idx]) ++ufs_idx;
		else ufs_idx = 0;

		if (uc_idx < 512) {
			ucbuf[uc_idx++] = c;
		} else {
			if (sight <= 2) {
				while (ucbp < 512) putchar(ucbuf[ucbp++]);
			}
			ft = 1;
		}
	}

	return 0;
}
