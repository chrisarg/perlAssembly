#!/home/chrisarg/perl5/perlbrew/perls/current/bin/perl
use strict;
use warnings;
use v5.36;
use Inline
  ASM     => 'DATA',
  AS      => 'nasm',
  ASFLAGS => '-f elf64',
  PROTO   => {
    add  => 'I16(I16,I16)',
    add8 => 'I16(I8,I8)',
  };

print "9 + 16 = ", add( 9, 16 ),  "\n";
print "9 + 16 = ", add8( 9, 16 ), "\n";

my @val = ( 1, 2, 3, 4, 5 );
my $s = pack( 'C*', @val );
say length($s);
__DATA__
__ASM__
; Use RIP-relative memory addressing
default rel

; Mark stack as non-executable for Binutils 2.39+
section .note.GNU-stack noalloc noexec nowrite progbits

SECTION .text

global add 
add: 
    add edi, esi
    mov eax, edi
    ret

global add8
add8: 
    add dil, sil
    movzx eax, dil
    ret
