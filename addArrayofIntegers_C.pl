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
use OpenMP::Environment;
use Inline (
    C         => 'DATA',
    ccflagsex => q{-fopenmp},
    lddlflags => join( q{ }, $Config::Config{lddlflags}, q{-fopenmp} ),
    myextlib  => ''
);

my $openmp_env = OpenMP::Environment->new;
$openmp_env->omp_num_threads(16);

my $benchmark = Benchmark::CSV->new(
    output      => './addArrayofIntegers.csv',
    sample_size => 1,
);

my $num_elements = 1_000_003;

## Create an array of $num_elements random integers, between -100, 100
my @array = map { int( rand(200) ) - 100 } 1 .. $num_elements;
my $array_double_ASM = pack "d*", @array;


say "Starting benchmark";
$benchmark->add_instance(
    'C_SIMD_wo_alloc' => sub {
        sum_array_SIMD_C( $array_double_ASM, scalar @array );
    },
);
$benchmark->add_instance(
    'C_SIMD_w_alloc' => sub {
        my $array_double_ASM = pack "d*", @array;
        sum_array_SIMD_C( $array_double_ASM, scalar @array );
    },
);
$benchmark->add_instance(
    'C_SIMD_OMP_wo_alloc' => sub {
        sum_array_SIMD_OMP_C( $array_double_ASM, scalar @array );
    },
);
$benchmark->add_instance(
    'C_SIMD_OMP_w_alloc' => sub {
        my $array_double_ASM = pack "d*", @array;
        sum_array_SIMD_OMP_C( $array_double_ASM, scalar @array );
    },
);

$benchmark->add_instance(
    'C_OMP_wo_alloc' => sub {
        sum_array_OMP_C( $array_double_ASM, scalar @array );
    },
);
$benchmark->add_instance(
    'C_OMP_w_alloc' => sub {
        my $array_double_ASM = pack "d*", @array;
        sum_array_OMP_C( $array_double_ASM, scalar @array );
    },
);

$benchmark->run_iterations(1000);

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
#include <omp.h>




void _ENV_set_num_threads() {
  char *num;
  num = getenv("OMP_NUM_THREADS");
  omp_set_num_threads(atoi(num));
}


double sum_array_SIMD_C(char *array_in, size_t length) {
    double sum = 0.0;
    double * array = (double *) array_in;
    #pragma omp simd reduction(+:sum)
    for (size_t i = 0; i < length; i++) {
        sum += array[i];
    }
    return sum;
}

double sum_array_SIMD_OMP_C(char *array_in, size_t length) {
    double sum = 0.0;
    double * array = (double *) array_in;
    _ENV_set_num_threads();
    #pragma omp parallel for simd reduction(+:sum) schedule(static,8)
    for (size_t i = 0; i < length; i++) {
        sum += array[i];
    }
    return sum;
}

double sum_array_OMP_C(char *array_in, size_t length) {
    double sum = 0.0;
    double * array = (double *) array_in;
    _ENV_set_num_threads();
    #pragma omp parallel for reduction(+:sum) schedule(static,8)
    for (size_t i = 0; i < length; i++) {
        sum += array[i];
    }
    return sum;
}
