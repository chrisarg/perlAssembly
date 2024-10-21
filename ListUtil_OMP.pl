#!/home/chrisarg/perl5/perlbrew/perls/current/bin/perl
use v5.38;

=head1 NAME
ListUtil_OMP.pl - Benchmark List::Util and list reduction operations with OMP

=head1 VERSION

Version 0.01 - created for London Perl & Raku Workshop 2024

=head1 USAGE
    
    perl ListUtil_OMP.pl-m 1 -s .3 -n 30 -r 100 -t 8 -e guided,1 -o ListUtil_OMP.csv

Simulates a large number of rounded doubles and times a number of reduction
operations (sum, product), using for loops in base Perl, List::Util, and 
OpenMP parallelized operations using Inline.

=head1 OPTIONS

Numerous options can control the scenarios to be tested (and none of them are 
required, since sensible defaults are provided):

=over 4

=item B<-n> I<number of elements>

Number of elements of the numeric array (the "size" of the problem)

=item B<-m> I<mean>

Mean of the lognormal distribution used to draw random numbers from

=item B<-s> I<standard deviation>

Standard deviation of the lognormal distribution used to draw random numbers from

=item B<-r> I<number of repetitions>

Number of repetitions for the benchmarking

=item B<-t> I<number of threads>

Maximum number of threads to use for the OpenMP operations (default is 2); the program
will test all scenarios from 1 to C<$c> threads.

=item B<-e> I<OpenMP schedule>

OpenMP schedule to use for the parallelized operations (default is guided,1). The
schedule is a comma-separated string with the first element being the schedule kind
(static, dynamic, guided, auto) and the second element being the chunk size. This
will be set up through the OMP_SCHEDULE environment variable at runtime. 

=item B<-o> I<output file>

Output file for the benchmarking results (default is ListUtil_OMP.csv)

=back

=head1 DEPENDENCIES

The script depends on the following modules:

=over 4

=item Benchmark::CSV

=item File::Copy

=item Getopt::Long

=item Inline::C

=item List::Util

=item Math::GSL::RNG

=item Math::GSL::Randist

=item OpenMP::Environment

=item PDL::Lite

=item PDL::IO::CSV

=item PDL::Stats::Basic

=back

=head1 TODO

Expand the script to include more operations (e.g. min and max) and more scenarios
including different types of data (e.g. text, integers, floating point numbers),
and OMP tasks.

=head1 AUTHOR

Christos Argyropoulos, C<< <chrisarg at cpan.org> >>
=cut

###############################################################################
## dependencies
use Benchmark::CSV;    # for proper statistical benchmarking
use File::Copy;        # for copying files
use Getopt::Long;      # for parsing command line options
use List::Util qw(min max sum product)
  ;                    # for finding the minimum and maximum values
use Math::GSL::RNG;
use Math::GSL::Randist qw/:all/;    # for generating random numbers
use OpenMP::Environment;            # for controlling the OpenMP environment
use PDL::Lite;
use PDL::IO::CSV ':all';
use PDL::Stats::Basic;
use Inline (
    C         => 'DATA',
    ccflagsex => q{-fopenmp},
    lddlflags => join( q{ }, $Config::Config{lddlflags}, q{-fopenmp} ),
    myextlib  => ''
);
###############################################################################
## process command line options : number of elements, mean and standard deviation
## We will generate text length and  integer values with a lognormal distribution
my $n = 1_000;               # number of elements
my $m = 1;                   # mean
my $s = 1;                   # standard deviation
my $r = 20;                  # number of repetitions
my $t = 2;                   # maximum number of threads to test for scalability
my $e = 'guided,1';          # OpenMP schedule
my $o = 'ListUtil_OMP.csv';  # output file
GetOptions(
    'n=i' => \$n,
    'm=f' => \$m,
    's=f' => \$s,
    'r=i' => \$r,
    't=i' => \$t,
    'e=s' => \$e,
    'o=s' => \$o,
);

my $env = OpenMP::Environment->new();    ## initialize the OpenMP environment

## simulate the text and numeric arrays
my $rng            = Math::GSL::RNG->new();
my @random_numbers = (undef) x $n;
for my $i ( 0 .. $n - 1 ) {
    $random_numbers[$i] = int( gsl_ran_lognormal( $rng->raw(), $m, $s ) );
}


## to avoid overflow issues, invert every other element in @random_numbers
## and zeros to ones
for my $i ( 0 .. $#random_numbers ) {
    $random_numbers[$i] = 1 if $random_numbers[$i] == 0;
    $random_numbers[$i] = 1.0/$random_numbers[$i] if $i % 2;
}

## initialize and set the benchmarks
my $benchmark = Benchmark::CSV->new(
    output      => $o,
    sample_size => 1,
);
$benchmark->add_instance( 'ListUtil_sum_num_1' => sub { sum(@random_numbers) },
);
$benchmark->add_instance(
    'ForLoop_sum_num_1' => sub {
        my $sum = 0.0;
        foreach my $i (@random_numbers) {
            $sum += $i;
        }
    },
);
$benchmark->add_instance( 'StC_sum_num_1' => sub { sum_with_C(\@random_numbers) },
);
for my $num_of_threads ( 1 .. $t ) {
    my $bench_name = sprintf "OMP_sum_num_%02d", $num_of_threads;
    $benchmark->add_instance(
        $bench_name => sub {
            $env->omp_num_threads($num_of_threads);
            $env->omp_schedule($e);
            set_openmp_schedule_from_env();
            set_openmp_num_threads_from_env();
            sum_with_OMP( \@random_numbers );
        },
    );
}    ## add the benchmarks for the OpenMP parallelized sum
$benchmark->add_instance(
    'ListUtil_prod_num_1' => sub { product(@random_numbers) }, );
$benchmark->add_instance(
    'ForLoop_prod_num_1' => sub {
        my $prod = 1.0;
        foreach my $i (@random_numbers) {
            $prod *= $i;
        }
    },
);
$benchmark->add_instance( 'StC_prod_num_1' => sub { prod_with_C(\@random_numbers) },
);
for my $num_of_threads ( 1 .. $t ) {
    my $bench_name = sprintf "OMP_prod_num_%02d", $num_of_threads;
    $benchmark->add_instance(
        $bench_name => sub {
            $env->omp_num_threads($num_of_threads);
            $env->omp_schedule($e);
            set_openmp_schedule_from_env();
            set_openmp_num_threads_from_env();
            prod_with_OMP( \@random_numbers );
        },
    );
}    ## add the benchmarks for the OpenMP parallelized sum
$benchmark->run_iterations($r);

# Load the CSV file

my @data = rcsv1D( $o, { text2bad => 1, header => 1 } );

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

## copy the $o to a file in which the size of the problem is included prior to the 
## extension .csv
my $o_new = $o;
$o_new =~ s/\.csv/_$n.csv/;
copy( $o, $o_new );
unlink $o;


__DATA__
__C__

#include <omp.h>
#include <stdlib.h>
#include <string.h>

void set_openmp_schedule_from_env();
void set_openmp_num_threads_from_env();
SV* sum_with_OMP(AV *array);
SV* prod_with_OMP(AV *array);
SV* sum_with_C(AV *array);
SV* prod_with_C(AV *array);

void set_openmp_schedule_from_env() {
    char *schedule_env = getenv("OMP_SCHEDULE");
    if (schedule_env != NULL) {
        char *kind_str = strtok(schedule_env, ",");
        char *chunk_size_str = strtok(NULL, ",");

        omp_sched_t kind;
        if (strcmp(kind_str, "static") == 0) {
            kind = omp_sched_static;
        } else if (strcmp(kind_str, "dynamic") == 0) {
            kind = omp_sched_dynamic;
        } else if (strcmp(kind_str, "guided") == 0) {
            kind = omp_sched_guided;
        } else {
            kind = omp_sched_auto;
        }
        int chunk_size = atoi(chunk_size_str);
        omp_set_schedule(kind, chunk_size);
    }
}

void set_openmp_num_threads_from_env() {
  char *num;
  num = getenv("OMP_NUM_THREADS");
  omp_set_num_threads(atoi(num));
}


SV* sum_with_OMP(AV *array) {
  int len = av_len(array) + 1;
  double retval = 0.0;
#pragma omp parallel
  {
#pragma omp for schedule(runtime) reduction(+:retval) nowait
    for (int i = 0; i < len; i++) {
      SV **elem = av_fetch_simple(array, i, 0); // perl 5.36 and above
      if (elem != NULL) {
        retval += (double) SvNV(*elem);
      }
    }
  }
  return newSVnv(retval); 
}

SV* sum_with_C(AV *array) {
  int len = av_len(array) + 1;
  double retval = 0.0;
  for (int i = 0; i < len; i++) {
    SV **elem = av_fetch_simple(array, i, 0); // perl 5.36 and above
    if (elem != NULL) {
      retval += (double) SvNV(*elem);
    }
  }
  return newSVnv(retval); 
}


SV* prod_with_OMP(AV *array) {
  int len = av_len(array) + 1;
  double retval = 1.0;
#pragma omp parallel
  {
#pragma omp for schedule(runtime) reduction(*:retval) nowait
    for (int i = 0; i < len; i++) {
      SV **elem = av_fetch_simple(array, i, 0); // perl 5.36 and above
      if (elem != NULL) {
        retval *= (double) SvNV(*elem);
      }
    }
  }
  return newSVnv(retval); 
}

SV* prod_with_C(AV *array) {
  int len = av_len(array) + 1;
  double retval = 1.0;
  for (int i = 0; i < len; i++) {
    SV **elem = av_fetch_simple(array, i, 0); // perl 5.36 and above
    if (elem != NULL) {
      retval *= (double) SvNV(*elem);
    }
  }
  return newSVnv(retval); 
}