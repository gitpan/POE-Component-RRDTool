
use strict;

sub POE::Kernel::ASSERT_ALL () { 1 }

use POE;

use lib qw(../blib/arch ../blib/lib);
use POE::Component::RRDTool;

use Test::More tests => 1;

#-----------------------#
#  Test 3: RRD update   #
#-----------------------#

my $ok = 1;

my @update_args = qw( test.rrd N:1 );

my $alias = 'controller';
POE::Component::RRDTool->new(
    -alias   => $alias,
);

POE::Session->create(
    inline_states => {
        _start => sub { 
            $_[KERNEL]->alias_set($_[ARG0]);
            $_[KERNEL]->post( 'rrdtool', 'update', @update_args );
            $_[KERNEL]->post( 'rrdtool', 'stop' );
        },
        'rrd_error' => sub { 
            $ok = 0; 
            print STDERR "ERROR: " . $_[ARG0] . "\n";  
        },
    },
    args => [ $alias ],
);

$poe_kernel->run();

ok($ok, 'the update was successful');

exit 0;
