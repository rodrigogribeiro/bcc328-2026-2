#include <stdio.h>
#include <stdlib.h>
#include <string.h>

long factorial(long n);
long factorialIter(long n);

long factorial(long n) {
    if ((n == 0L)) {
        return 1L;
    } else {
        return (n * factorial((n - 1L)));
    }
}

long factorialIter(long n) {
    long result = 1L;
    long i = n;
    while ((i > 0L)) {
        result = (result * i);
        i = (i - 1L);
    }
    return result;
}

int main(void) {
    long n = 0L;
    printf("%s", "n: ");
    scanf("%ld", &n);
    printf("%ld\n", (long)(factorial(n)));
    printf("%ld\n", (long)(factorialIter(n)));
    return 0;
}
