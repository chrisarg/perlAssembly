#!/home/chrisarg/perl5/perlbrew/perls/current/bin/perl
use v5.36;

use List::Util qw(sum);
use Benchmark::CSV;
use PDL::Lite;
use PDL::NiceSlice;
use PDL::IO::Misc;
use PDL::IO::CSV ':all';
use PDL::Stats::Basic;
use Time::HiRes qw(time);
use Inline C => 'DATA';
use Inline
  ASM     => 'DATA',
  AS      => 'nasm',
  ASFLAGS => '-f elf64',
  PROTO   => {
    sum_array                       => 'double(char *,size_t)',
    sum_array_blank                 => 'double(char *,size_t)',
    sum_array_doubles               => 'double(char *,size_t)',
    sum_array_doubles_AVX_unaligned => 'double(char *,size_t)',

  };

my $benchmark = Benchmark::CSV->new(
    output      => './addArrayofIntegers.csv',
    sample_size => 1,
);

my $num_elements = 1_000_003;
## Create an array of $num_elements random integers, between -100, 100
my @array = map { int( rand(200) ) - 100 } 1 .. $num_elements;

my $array_byte_ASM   = pack "c*", @array;
my $array_double_ASM = pack "d*", @array;

my $ndarray = pdl( \@array );


$benchmark->add_instance(
    'ASM_wo_alloc' => sub {
        sum_array( $array_byte_ASM, scalar @array );
    },
);
$benchmark->add_instance(
    'ASM_doubles_wo_alloc' => sub {
        sum_array_doubles( $array_double_ASM, scalar @array );
    },
);
$benchmark->add_instance(
    'ASM_blank' => sub {
        sum_array_blank( $array_double_ASM, scalar @array );
    },
);
$benchmark->add_instance(
    'ASM_w_alloc' => sub {
        my $array = pack "d*", @array;
        sum_array( $array, scalar @array );
    },
);
$benchmark->add_instance(
    'ASM_doubles_w_alloc' => sub {
        my $array = pack "d*", @array;
        sum_array_doubles( $array, scalar @array );
    },
);
$benchmark->add_instance(
    'ASM_doubles_AVX_w_alloc' => sub {
        my $array = pack "d*", @array;
        sum_array_doubles_AVX_unaligned( $array, scalar @array );
    },
);
$benchmark->add_instance(
    'ASM_doubles_AVX_wo_alloc' => sub {
        sum_array_doubles_AVX_unaligned( $array_double_ASM, scalar @array );
    },
);
$benchmark->add_instance(
    'C_doubles_w_alloc' => sub {
        my $array_double_ASM = pack "d*", @array;
        sum_array_C( $array_double_ASM, scalar @array );
    },
);
$benchmark->add_instance( 'C_doubles_wo_alloc' =>
      sub { sum_array_C( $array_double_ASM, scalar @array ) }, );
$benchmark->add_instance( 'ListUtil'     => sub { sum(@array) }, );
$benchmark->add_instance( 'PDL_wo_alloc' => sub { $ndarray->sum }, );
$benchmark->add_instance( 'PDL_w_alloc'  => sub { pdl( \@array )->sum }, );
$benchmark->add_instance(
    'ForLoop' => sub {
        my $sum = 0;
        foreach my $i (@array) {
            $sum += $i;
        }
    },
);

$benchmark->run_iterations(100);

# Load the CSV file

my @data = rcsv1D( 'addArrayofIntegers.csv', { text2bad => 1, header => 1 } );

my %summary_stats = ();

foreach my $col ( 0 .. $#data ) {
    my $pdl    = pdl( $data[$col] );
    my $mean   = $pdl->average;
    my $stddev = $pdl->stdv_unbiased;
    my $median = $pdl->median;
    $summary_stats{ $data[$col]->hdr->{col_name} } =
      { mean => $mean, stddev => $stddev, median => $median };
}

# Get the column names from the first row
my @column_names = sort keys %{ $summary_stats{ ( keys %summary_stats )[0] } };

# Define the width for each column
my $width_name = 24;
my $width_col  = 10;

# Print the column names
printf "%-${width_name}s", '';
printf "%${width_col}s",   $_ for @column_names;
print "\n";

# Print each row
foreach my $row_name ( sort keys %summary_stats ) {
    printf "%-${width_name}s", $row_name;
    printf "%${width_col}.1e", $summary_stats{$row_name}{$_} for @column_names;
    print "\n";
}

unlink 'addArrayofIntegers.csv';
## load the CSV file and print a summary of the results using PDL

__DATA__
__C__

double sum_array_C(char *array_in, size_t length) {
    double sum = 0.0;
    double * array = (double *) array_in;
    for (size_t i = 0; i < length; i++) {
        sum += array[i];
    }
    return sum;
}
__ASM__
NSE    equ 4 ; number of SIMD double elements per iteration
DOUBLE equ 8 ; number of bytes per double

; Use RIP-relative memory addressing
default rel

; Mark stack as non-executable for Binutils 2.39+
section .note.GNU-stack noalloc noexec nowrite progbits

SECTION .text

global sum_array
sum_array:
 ; Initialize xmm0 to 0 (this will hold our sum)
    xorpd xmm0, xmm0

    ; Loop over each element of the array
    .loop:
        ; Check if we've processed all elements
        test rsi, rsi
        jz .end

        ; Load the current element into eax (as an 8-bit integer)
        movsx eax, byte [rdi]

        ; Convert the integer in eax to a double in xmm1
        cvtsi2sd xmm1, eax

        ; Add the value in xmm1 to our running total in xmm0
        addsd xmm0, xmm1

        ; Move to the next element
        add rdi, 1

        ; Decrement our counter
        dec rsi

        jmp .loop
    .end:
  ret

global sum_array_doubles
sum_array_doubles: ; based on Kusswurm listing 5-7c
    ; Initialize
    vxorpd xmm0, xmm0, xmm0 ; sum = 0.0
    sub rdi, 8              ; rdi = &array[-1]

    Loop1:
        add rdi, DOUBLE
        vaddsd xmm0, xmm0, qword [rdi]
        sub rsi, 1
        jnz Loop1
    ret


global sum_array_doubles_AVX_unaligned
sum_array_doubles_AVX_unaligned: ; based on Kusswurm listing 9-4d
    vxorpd ymm0, ymm0, ymm0         ; sum = 0.0      

                                    ; i = 0 in the comments of this block
    lea r10,[rdi - DOUBLE]          ; r10 = &array[i-1]
    cmp rsi, NSE                    ; check if we have at least NSE elements
    jb Remainder_AVX                ; if not, jump to remainder
    lea r10, [rdi-NSE * DOUBLE]     ; r10 = &array[i-NSE]


    Loop1_AVX:
        add r10, DOUBLE * NSE        ; r10 = &array[i]
        vaddpd ymm0, ymm0, [r10]     ; sum += array[i]
        sub rsi, NSE                 ; decrement the counter
        cmp rsi, NSE                 ; check if we have at least NSE elements
        jae Loop1_AVX                ; if so, loop again

    ; Reduce packed sum using SIMD addition
    vextractf128 xmm1, ymm0, 1      ; extract the high 128 bits
    vaddpd xmm2, xmm1, xmm0         ; sum += high 128 bits
    vhaddpd xmm0, xmm2, xmm2        ; sum += low 128 bits
    test rsi, rsi                   ; check if we have any elements left
    jz End_AVX                      ; if not, jump to the end

    add r10, DOUBLE * NSE  - DOUBLE ; r10 = &array[i-1]
    

    ; Handle the remaining elements
    Remainder_AVX:
        add r10, DOUBLE
        vaddsd xmm0, xmm0, qword [r10]
        sub rsi, 1
        jnz Remainder_AVX

    End_AVX:
    ;vmovsd xmm0, xmm5
    ret

global sum_array_blank
sum_array_blank:
    ; Initialize sum to 0
    vxorpd xmm0, xmm0, xmm0
    ret ; send a zero back
