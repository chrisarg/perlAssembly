# perlAssembly

This is probably one of the things that should never be allowed to exist, but why not use Perl and its capabilities to inline foreign code, to FAFO with assembly without a build system? Everything in a single file! In the process one may find ways to use Perl to enhance NASM and vice versa. But for now, I make no such claims : I am just using the perlAssembly git repo to illustrate how one can use Perl to drive (and learn to code!) assembly programs from a single file. 

## x86-64 examples

### addIntegers.pl
Simple integer addition in Perl

### addArrayofIntegers.pl
Explore multiple equivalent ways to add *large* arrays in Perl:
* ASM\_blank : test the speed of calling ASM from Perl (no computations are done)
* ASM\_doubles : pass the array as a packed string of doubles and do scalar double floating addition in assembly
* ASM\_doubles\_AVX: pass the array as a packed string of doubles and do packed floating point addition in assembly
* ForLoop : standard for loop in Perl
* ListUtil: sum function from list utilities
* PDL : uses summation in PDL

Varieties w\_alloc : allocate memory for each iteration to test the speed of pack, those marked
as wo\_alloc, use a pre-computed data structure to pass the array to the underlying code. 
The first benchmark gives the true cost of offloading summation to of a Perl array to a given 
function when the source data are in Perl. The second, just benchmarks the calculation speed. 
For the example considered here, it makes ZERO senso to offload the calculation as ListUtil is
already within 15% of the assembly solution. If however, one was managing the array, not as a 
Perl array, but as an area in memory through a Perl object, then one COULD consider offloading.

#### Results
                              mean    median    stddev
ASM\_blank                  2.3e-06   2.0e-06   1.1e-06
ASM\_doubles\_AVX\_w\_alloc    3.6e-03   3.5e-03   4.2e-04
ASM\_doubles\_AVX\_wo\_alloc   3.0e-04   2.9e-04   2.7e-05
ASM\_doubles\_w\_alloc        4.3e-03   4.1e-03   4.5e-04
ASM\_doubles\_wo\_alloc       8.9e-04   8.7e-04   3.0e-05
ASM\_w\_alloc                4.3e-03   4.2e-03   4.5e-04
ASM\_wo\_alloc               9.2e-04   9.1e-04   4.1e-05
ForLoop                    1.9e-02   1.9e-02   2.6e-04
ListUtil                   4.5e-03   4.5e-03   1.4e-04
PDL\_w\_alloc                2.1e-02   2.1e-02   6.7e-04
PDL\_wo\_alloc               9.2e-04   9.0e-04   3.9e-05

### Disclaimer
The code here is NOT meant to be portable. I code in Linux and in x86-64, so if you are looking into Window's ABI or ARM, you will be disappointed. But as my knowledge of ARM assembly grows, I intend to rewrite some examples in Arm assembly!
