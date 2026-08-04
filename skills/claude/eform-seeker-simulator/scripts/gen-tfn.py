#!/usr/bin/env python3
"""Generate one checksum-valid 9-digit Australian Tax File Number.

TFN checksum: sum of (digit[i] * weight[i]) mod 11 == 0,
weights = [1,4,3,7,5,8,6,9,10]. Prints the raw 9-digit string (no spaces);
the eForm TFN field strips non-digits anyway.

Usage: scripts/gen-tfn.py            # prints one valid TFN
       scripts/gen-tfn.py 5          # print 5 valid TFNs
"""

import random
import sys

WEIGHTS = [1, 4, 3, 7, 5, 8, 6, 9, 10]


def gen_tfn() -> str:
    while True:
        digits = [random.randint(0, 9) for _ in range(8)]
        total = sum(digits[i] * WEIGHTS[i] for i in range(8))
        # 9th weight is 10; find a digit 0..9 with (total + d*10) % 11 == 0.
        # (~1 in 11 first-8 draws has no valid 9th digit -> retry.)
        ninth = next((d for d in range(10) if (total + d * 10) % 11 == 0), None)
        if ninth is not None:
            digits.append(ninth)
            return "".join(str(d) for d in digits)


def main() -> None:
    count = int(sys.argv[1]) if len(sys.argv) > 1 else 1
    for _ in range(count):
        print(gen_tfn())


if __name__ == "__main__":
    main()